import 'package:flutter/material.dart';
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

import 'guides.dart';

// ---------------------------------------------------------------------------
// Tutor: small LLMs — turn a receipt, a chat or an SMS into structured data
// on device, and answer a live question with a tool. Runs the guides on one
// model and shows what the model returned and what the app parsed from it.
//
// Token: injected at build time via
//   flutter run --dart-define-from-file=secrets.json
// ---------------------------------------------------------------------------
const _apiToken = String.fromEnvironment('TS_API_TOKEN');

/// A bundle path or repo id instead of the picked model.
const _llmBundle = String.fromEnvironment('LLM_BUNDLE');

class _Pack {
  final String id;
  final String repo;
  const _Pack(this.id, this.repo);
}

const _packs = [
  _Pack('LFM2.5 230M', 'TheStageAI/LFM2.5-230M'),
  _Pack('LFM2.5 350M', 'TheStageAI/LFM2.5-350M'),
  _Pack('LFM2.5 1.2B', 'TheStageAI/LFM2.5-1.2B'),
  _Pack('LFM3 1.7B', 'TheStageAI/LFM3-1.7B'),
  _Pack('Qwen3.5 0.8B', 'TheStageAI/Qwen3.5-0.8B'),
  _Pack('Qwen3.5 2B', 'TheStageAI/Qwen3.5-2B'),
  _Pack('Qwen3.5 4B', 'TheStageAI/Qwen3.5-4B'),
];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TutorApp());
}

class TutorApp extends StatelessWidget {
  const TutorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tutor: small LLMs',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const TutorScreen(),
    );
  }
}

class TutorScreen extends StatefulWidget {
  const TutorScreen({super.key});

  @override
  State<TutorScreen> createState() => _TutorScreenState();
}

class _TutorScreenState extends State<TutorScreen> {
  static const _modelName = 'tutor_llm';

  _Pack _pack = _packs[1];
  final Set<int> _guides = {1, 2, 3, 4, 5};
  String? _loadedRepo;
  bool _supportsTools = false;
  bool _initialized = false;
  bool _running = false;
  String? _phase;
  double? _fraction;
  final _log = StringBuffer();

  String get _repo => _llmBundle.isNotEmpty ? _llmBundle : _pack.repo;

  void _append(String line) {
    if (!mounted) return;
    setState(() => _log.writeln(line));
  }

  Future<void> _ensureModel() async {
    if (!_initialized) {
      await TheStageFlutterSDK.initialize(api_token: _apiToken);
      _initialized = true;
    }
    if (_loadedRepo == _repo) return;
    if (_loadedRepo != null) {
      await TheStageFlutterSDK.stop_model(model_name: _modelName);
      _loadedRepo = null;
    }
    final sub = TheStageFlutterSDK.on_progress.listen((e) {
      if (e['model_name'] != _modelName || !mounted) return;
      setState(() {
        _phase = e['phase'] as String?;
        _fraction = (e['progress'] as num?)?.toDouble();
      });
    });
    try {
      final status = await TheStageFlutterSDK.start_model(
        model_name: _modelName,
        engines_path: _repo,
        model_type: 'the-stage-llm',
      );
      final features = status['features'] as Map?;
      _supportsTools =
          (features?['tools'] as Map?)?['supported'] == true;
      _loadedRepo = _repo;
    } finally {
      await sub.cancel();
      if (mounted) setState(() => _phase = null);
    }
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _log.clear();
    });
    try {
      await _ensureModel();
      _append('model=$_repo guides=${(_guides.toList()..sort()).join(",")}');
      final guides = Guides(
        _modelName,
        _append,
        supportsTools: _supportsTools,
      );
      for (final g in _guides.toList()..sort()) {
        await guides.run(g);
      }
    } catch (e) {
      _append('error: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    if (_loadedRepo != null) {
      TheStageFlutterSDK.stop_model(model_name: _modelName);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tutor: small LLMs')),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_apiToken.isEmpty)
                const Text(
                  'TS_API_TOKEN not set. Run with '
                  '--dart-define-from-file=secrets.json',
                  style: TextStyle(color: Colors.red),
                ),
              if (_llmBundle.isEmpty)
                Wrap(spacing: 8, children: [
                  for (final p in _packs)
                    ChoiceChip(
                      label: Text(p.id),
                      selected: _pack == p,
                      onSelected:
                          _running ? null : (_) => setState(() => _pack = p),
                    ),
                ])
              else
                Text('Model: $_llmBundle'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final g in Guides.titles.keys)
                  FilterChip(
                    label: Text('$g · ${Guides.titles[g]}'),
                    selected: _guides.contains(g),
                    onSelected: _running
                        ? null
                        : (on) => setState(
                            () => on ? _guides.add(g) : _guides.remove(g)),
                  ),
              ]),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _running || _apiToken.isEmpty || _guides.isEmpty
                    ? null
                    : _run,
                icon: const Icon(Icons.play_arrow),
                label: Text(_running ? 'Running…' : 'Run guides'),
              ),
              if (_phase != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _phase == 'downloading' ? _fraction : null,
                ),
                Text('$_phase', style: const TextStyle(color: Colors.grey)),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black26),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: SelectableText(
                      _log.toString(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

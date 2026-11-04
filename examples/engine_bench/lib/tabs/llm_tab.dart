import 'dart:async';

import 'package:flutter/material.dart';
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

import '../backend/bench_session.dart';
import '../backend/load_state.dart';
import '../backend/sdk_host.dart';
import '../widgets/bench_widgets.dart';

// ----------------------------------------------------------------------
// LLM catalog
// ----------------------------------------------------------------------
// On-device text LLMs driven through the generic `the-stage-llm`
// model type. Engines load from Hugging Face on first use; the SDK
// downloads + caches per model.
class _LlmModel {
  const _LlmModel(this.id, this.displayName, this.repo);
  final String id;
  final String displayName;
  final String repo;
}

const _llmRevision = String.fromEnvironment(
  'LLM_REVISION',
  defaultValue: '',
);

const _llmModels = [
  _LlmModel('lfm2.5-230m', 'LFM2.5 230M', 'TheStageAI/LFM2.5-230M'),
  _LlmModel('lfm2.5-350m', 'LFM2.5 350M', 'TheStageAI/LFM2.5-350M'),
  _LlmModel('lfm2.5-1.2b', 'LFM2.5 1.2B', 'TheStageAI/LFM2.5-1.2B'),
  _LlmModel('lfm3-1.7b', 'LFM3 1.7B', 'TheStageAI/LFM3-1.7B'),
  _LlmModel('qwen3.5-0.8b', 'Qwen3.5 0.8B', 'TheStageAI/Qwen3.5-0.8B'),
  _LlmModel('qwen3.5-2b', 'Qwen3.5 2B', 'TheStageAI/Qwen3.5-2B'),
  _LlmModel('qwen3.5-4b', 'Qwen3.5 4B', 'TheStageAI/Qwen3.5-4B'),
  // 8 Elite and 8 Elite Gen 5 only.
  _LlmModel('qwen3.5-9b', 'Qwen3.5 9B', 'TheStageAI/Qwen3.5-9B'),
];

// ----------------------------------------------------------------------
// LlmTab
// ----------------------------------------------------------------------
class LlmTab extends StatefulWidget {
  const LlmTab({super.key});

  @override
  State<LlmTab> createState() => _LlmTabState();
}

class _LlmTabState extends State<LlmTab> {
  static const _modelName = 'bench_llm';
  static const _warmupRuns = 2;

  _LlmModel _selected = _llmModels.first;
  // The loaded model and its MTP choice (see [loadKey]).
  String? _loadedKey;
  // MTP (the bundle's drafter); changing it reloads the model.
  bool _mtp = true;
  // From the start_model status: the loaded model has a drafter.
  bool _mtpSupported = false;

  final _promptCtl =
      TextEditingController(text: 'List 25 facts about London.');
  int _maxNew = 128;
  int _runs = 5;

  bool _running = false;
  String _status = 'tap Generate';
  String _statsLine = '';
  String _output = '';
  String? _loadPhase;
  double? _loadFraction;
  StreamSubscription<Map<String, dynamic>>? _progressSub;

  @override
  void dispose() {
    _promptCtl.dispose();
    _progressSub?.cancel();
    _stopModel();
    super.dispose();
  }

  // --------------------------------------------------------------------
  // Model load (with progress)
  // --------------------------------------------------------------------
  Future<void> _stopModel() async {
    try {
      await TheStageFlutterSDK.stop_model(model_name: _modelName);
    } catch (_) {}
  }

  Future<void> _ensureModel(_LlmModel m) async {
    final key = loadKey(m.repo, mtp: _mtp);
    if (_loadedKey == key) return;
    await SdkHost.instance.ensureInitialized();
    await _stopModel();
    // Nothing is loaded under the handle any more: a failed start
    // below must not leave the old key claiming it is.
    _loadedKey = null;
    _progressSub = TheStageFlutterSDK.on_progress.listen((e) {
      if (!mounted || !isProgressFor(e, _modelName)) return;
      setState(() {
        _loadPhase = e['phase'] as String?;
        _loadFraction = (e['progress'] as num?)?.toDouble();
      });
    });
    try {
      final status = await TheStageFlutterSDK.start_model(
        model_type: 'the-stage-llm',
        model_name: _modelName,
        engines_path: m.repo,
        revision: _llmRevision,
        config: {'use_mtp': _mtp},
      );
      _loadedKey = key;
      final mtp = (status['features'] as Map?)?['mtp'] as Map?;
      if (mounted) {
        setState(() => _mtpSupported = mtp?['supported'] == true);
      }
    } finally {
      await _progressSub?.cancel();
      _progressSub = null;
      if (mounted) setState(() => _loadPhase = null);
    }
  }

  // --------------------------------------------------------------------
  // Generate (streaming — honest TTFT + feel)
  // --------------------------------------------------------------------
  Future<void> _generate() async {
    if (_running) return;
    final m = _selected;
    final prompt = _promptCtl.text.trim();
    if (prompt.isEmpty) return;
    setState(() {
      _running = true;
      _output = '';
      _statsLine = '';
      _status = 'loading ${m.displayName}...';
    });
    try {
      await _ensureModel(m);
      setState(() => _status = 'generating...');
      final stream = TheStageFlutterSDK.infer_stream(
        model_name: _modelName,
        input_json: {'inputs': _inputs(prompt)},
      );
      await for (final chunk in stream) {
        final delta = chunk['delta']?.toString() ?? '';
        if (delta.isNotEmpty && mounted) {
          setState(() => _output += delta);
        }
        if (chunk['is_final'] == true) {
          final tps = (chunk['tokens_per_second'] as num?)?.toDouble() ?? 0;
          final ttftMs =
              ((chunk['time_to_first_token'] as num?)?.toDouble() ?? 0) *
                  1000;
          final tokens =
              (chunk['generated_tokens'] as num?)?.toInt() ?? 0;
          setState(() {
            _statsLine = '${_label(m)} - $tokens tok - '
                'decode ${tps.toStringAsFixed(1)} tok/s - '
                'TTFT ${ttftMs.toStringAsFixed(0)} ms';
            _status = 'done';
          });
        }
      }
    } catch (e) {
      setState(() => _status = 'error: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  // --------------------------------------------------------------------
  // Benchmark (warmup + N quiet runs — no UI writes during decode)
  // --------------------------------------------------------------------
  Future<Map<String, dynamic>> _runInferSilent(String prompt) async {
    final stream = TheStageFlutterSDK.infer_stream(
      model_name: _modelName,
      input_json: {'inputs': _inputs(prompt)},
    );
    Map<String, dynamic> last = const {};
    await for (final chunk in stream) {
      if (chunk['is_final'] == true) last = chunk;
    }
    return last;
  }

  Future<void> _benchmark() async {
    if (_running) return;
    final m = _selected;
    final prompt = _promptCtl.text.trim();
    if (prompt.isEmpty) return;
    final n = _runs < 1 ? 1 : _runs;
    setState(() {
      _running = true;
      _output = '';
      _statsLine = '';
      _status = 'preparing...';
    });
    try {
      await _ensureModel(m);
      for (var w = 0; w < _warmupRuns; w++) {
        setState(() => _status = 'warmup ${w + 1}/$_warmupRuns...');
        await _runInferSilent(prompt);
      }
      final tokS = <double>[];
      final ttftMs = <double>[];
      var tokens = 0;
      for (var k = 0; k < n; k++) {
        setState(() => _status = 'run ${k + 1}/$n...');
        final r = await _runInferSilent(prompt);
        tokS.add((r['tokens_per_second'] as num?)?.toDouble() ?? 0);
        ttftMs.add(
          ((r['time_to_first_token'] as num?)?.toDouble() ?? 0) * 1000,
        );
        tokens = (r['generated_tokens'] as num?)?.toInt() ?? tokens;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      final best = maxOf(tokS) ?? 0;
      final med = median(tokS) ?? 0;
      BenchSession.instance.add(BenchRecord(
        kind: 'llm',
        model: _label(m),
        runs: n,
        prompt: prompt,
        maxNewTokens: _maxNew,
        metrics: {
          'best_tok_s': best,
          'median_tok_s': med,
          'mean_tok_s': mean(tokS) ?? 0,
          'mean_ttft_ms': mean(ttftMs) ?? 0,
          'tokens': tokens.toDouble(),
        },
        perRun: {'tok_s': tokS, 'ttft_ms': ttftMs},
      ));
      setState(() {
        _statsLine = '${_label(m)} - best ${best.toStringAsFixed(1)} / '
            'median ${med.toStringAsFixed(1)} tok/s';
        _status = 'done';
      });
    } catch (e) {
      setState(() => _status = 'error: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  // Thinking off: the bench times answers, and a reasoning model
  // would spend the token budget on its reasoning.
  Map<String, dynamic> _inputs(String prompt) => {
        'prompt': prompt,
        'max_new_tokens': _maxNew,
        'enable_thinking': false,
      };

  // The model's name, with " + MTP" when its drafter runs.
  String _label(_LlmModel m) =>
      _mtp && _mtpSupported ? '${m.displayName} + MTP' : m.displayName;

  // --------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return BenchScaffold(
      title: 'LLM bench',
      children: [
        ModelChips<_LlmModel>(
          models: _llmModels,
          selected: _selected,
          label: (m) => m.displayName,
          enabled: !_running,
          onSelected: (m) => setState(() {
            _selected = m;
            // Known again once the new model has loaded.
            if (_loadedKey?.startsWith('${m.repo}|') != true) {
              _mtpSupported = false;
            }
          }),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _promptCtl,
          enabled: !_running,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Prompt',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: StepperTile(
              label: 'max',
              value: _maxNew,
              min: 16,
              max: 1024,
              step: 16,
              enabled: !_running,
              onChanged: (v) => setState(() => _maxNew = v),
            ),
          ),
          Expanded(
            child: StepperTile(
              label: 'runs',
              value: _runs,
              min: 1,
              max: 20,
              step: 1,
              enabled: !_running,
              onChanged: (v) => setState(() => _runs = v),
            ),
          ),
        ]),
        if (_mtpSupported)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('MTP (speculative decoding)'),
            subtitle: const Text('Applies at the next load.'),
            value: _mtp,
            onChanged: _running ? null : (v) => setState(() => _mtp = v),
          ),
        if (_loadPhase != null)
          LoadProgress(phase: _loadPhase!, fraction: _loadFraction),
        const SizedBox(height: 12),
        ActionRow(
          running: _running,
          onGenerate: _generate,
          onBenchmark: _benchmark,
        ),
        const SizedBox(height: 12),
        OutputBox(text: _output),
        const SizedBox(height: 8),
        StatusLine(text: _statsLine.isEmpty ? _status : _statsLine),
      ],
    );
  }
}

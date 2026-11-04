import 'package:flutter/material.dart';

import 'lang_parser.dart';
import 'phrases.dart';
import 'tutor_model.dart';

// ---------------------------------------------------------------------------
// Tutor TTS — mixed-language streaming speech with NeuTTS nano
// multilingual.
//
// Token: injected at build time via
//   flutter run --dart-define-from-file=secrets.json
// ---------------------------------------------------------------------------
const _apiToken = String.fromEnvironment('TS_API_TOKEN');

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
      title: 'Tutor TTS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
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
  final _model = TutorModel();
  final _scriptCtl = TextEditingController(
    text: TutorPhraseBook.all.first.tagged,
  );

  @override
  void initState() {
    super.initState();
    _model.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _model.removeListener(_onUpdate);
    _model.dispose();
    _scriptCtl.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  // The tags the current script uses, in order of first use.
  List<String> get _tags {
    try {
      final seen = <String>[];
      for (final s in LangTagParser.parse(_model.script)) {
        if (!seen.contains(s.tag)) seen.add(s.tag);
      }
      return seen;
    } on LangParseError {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _model;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Tutor TTS')),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_apiToken.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'TS_API_TOKEN not set. Run with '
                    '--dart-define-from-file=secrets.json',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              if (m.loading) ...[
                LinearProgressIndicator(
                  value: m.loadPhase == 'downloading' ? m.loadFraction : null,
                ),
                const SizedBox(height: 8),
              ],
              DropdownButtonFormField<TutorPhrase>(
                initialValue: m.selected,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Phrase',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final p in TutorPhraseBook.all)
                    DropdownMenuItem(value: p, child: Text(p.title)),
                ],
                onChanged: m.running
                    ? null
                    : (p) {
                        if (p == null) return;
                        m.select(p);
                        _scriptCtl.text = p.tagged;
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _scriptCtl,
                enabled: !m.running,
                minLines: 4,
                maxLines: 10,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Tagged script (<en>…</en><es>…</es>)',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                onChanged: (v) => setState(() => m.script = v),
              ),
              if (m.loaded && m.voices.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final tag in _tags) _voiceRow(tag),
              ],
              const SizedBox(height: 12),
              Row(children: [
                if (!m.loaded)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: m.loading || _apiToken.isEmpty
                          ? null
                          : () => m.load(_apiToken),
                      icon: const Icon(Icons.download),
                      label: Text(m.loading ? 'Loading…' : 'Load model'),
                    ),
                  )
                else
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: m.running ? null : m.play,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play'),
                    ),
                  ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: m.running ? m.stop : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
              ]),
              const SizedBox(height: 16),
              Text(m.status),
              if (m.stats.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  m.stats,
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _voiceRow(String tag) {
    final m = _model;
    final current = m.voiceFor[tag] ?? m.defaultVoice;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        SizedBox(width: 96, child: Text(LangTagParser.tagToLanguage[tag]!)),
        Expanded(
          child: DropdownButton<String>(
            value: m.voices.contains(current) ? current : null,
            isExpanded: true,
            items: [
              for (final v in m.voices)
                DropdownMenuItem(value: v, child: Text(v)),
            ],
            onChanged: m.running
                ? null
                : (v) {
                    if (v != null) m.setVoice(tag, v);
                  },
          ),
        ),
      ]),
    );
  }
}

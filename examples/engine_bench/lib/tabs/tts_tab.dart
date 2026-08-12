import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

import '../backend/bench_session.dart';
import '../backend/sdk_host.dart';
import '../widgets/bench_widgets.dart';

// ----------------------------------------------------------------------
// TtsTab — NeuTTS nano-multilingual streaming synth + benchmark
// ----------------------------------------------------------------------
// Android TTS = NeuTTS only (the iOS EngineBench's Qwen3-TTS row has no
// Android counterpart, so it is dropped here). Synthesize streams audio
// through the SDK's built-in player and reports first-chunk / RTF / tok/s;
// Benchmark runs N silent synths and records the medians.
const _ttsEnginesPath = String.fromEnvironment(
  'TTS_ENGINE_PATH',
  defaultValue: 'TheStageAI/neutts-nano-multilingual',
);
const _ttsRevision = String.fromEnvironment(
  'TTS_REVISION',
  defaultValue: 'android',
);

class TtsTab extends StatefulWidget {
  const TtsTab({super.key});

  @override
  State<TtsTab> createState() => _TtsTabState();
}

class _TtsTabState extends State<TtsTab> {
  final _controller = TTSController(
    modelName: 'bench_tts',
    enginesPath: _ttsEnginesPath,
    modelType: 'neutts',
    revision: _ttsRevision,
    availableVoices: const ['dave', 'bril', 'jo', 'paul'],
    defaultVoice: 'dave',
  );

  final _textCtl = TextEditingController(
    text: 'Hello! This is a test of the new text to speech model.',
  );
  int _runs = 3;
  bool _running = false;
  String _status = 'tap Synthesize';
  String _statsLine = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _controller.removeListener(_onUpdate);
    _controller.dispose();
    _textCtl.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _ensureReady() async {
    if (_controller.modelReady) return;
    await SdkHost.instance.ensureInitialized();
    await _controller.initialize();
  }

  // --------------------------------------------------------------------
  // Synthesize (streaming + playback)
  // --------------------------------------------------------------------
  Future<void> _synthesize() async {
    if (_running) return;
    final text = _textCtl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _running = true;
      _statsLine = '';
      _status = 'loading...';
    });
    try {
      await _ensureReady();
      setState(() => _status = 'synthesizing...');
      await _controller.startStream(text);
      // startStream returns once streaming begins; the controller's
      // listener refreshes stats. Wait for it to finish before
      // re-enabling the buttons.
      while (_controller.generating) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final s = _controller.stats;
      if (s != null) {
        setState(() {
          _statsLine = '${s.audioDuration.toStringAsFixed(2)}s audio - '
              'TTFA ${((s.timeToFirstAudio ?? 0) * 1000).toStringAsFixed(0)} ms - '
              'rtf ${(s.rtf ?? 0).toStringAsFixed(2)} - '
              '${(s.tokensPerSecond ?? 0).toStringAsFixed(1)} tok/s';
        });
      }
      setState(() => _status = 'done');
    } catch (e) {
      setState(() => _status = 'error: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  // --------------------------------------------------------------------
  // Benchmark (N silent synths — no playback, records medians)
  // --------------------------------------------------------------------
  Future<Map<String, double>> _runSilent(String text) async {
    final stream = TheStageFlutterSDK.infer_stream(
      model_name: 'bench_tts',
      input_json: {'text': text},
    );
    var audioSeconds = 0.0;
    var totalSeconds = 0.0;
    var tps = 0.0;
    await for (final chunk in stream) {
      final audio = chunk['audio'] as Float32List?;
      final sr = (chunk['sample_rate'] as num?)?.toInt() ?? 24000;
      if (audio != null && audio.isNotEmpty) {
        audioSeconds += audio.length / sr;
      }
      if (chunk['is_final'] == true) {
        totalSeconds = (chunk['total_seconds'] as num?)?.toDouble() ?? 0;
        tps = (chunk['tokens_per_second'] as num?)?.toDouble() ?? 0;
      }
    }
    final rtf = totalSeconds > 0 ? audioSeconds / totalSeconds : 0.0;
    return {'tok_s': tps, 'rtf': rtf};
  }

  Future<void> _benchmark() async {
    if (_running) return;
    final text = _textCtl.text.trim();
    if (text.isEmpty) return;
    final n = _runs < 1 ? 1 : _runs;
    setState(() {
      _running = true;
      _statsLine = '';
      _status = 'preparing...';
    });
    try {
      await _ensureReady();
      setState(() => _status = 'warmup...');
      await _runSilent(text);
      final tokS = <double>[];
      final rtf = <double>[];
      for (var k = 0; k < n; k++) {
        setState(() => _status = 'run ${k + 1}/$n...');
        final r = await _runSilent(text);
        tokS.add(r['tok_s'] ?? 0);
        rtf.add(r['rtf'] ?? 0);
      }
      BenchSession.instance.add(BenchRecord(
        kind: 'tts',
        model: 'NeuTTS nano multilingual',
        voice: _controller.selectedVoice,
        runs: n,
        prompt: text,
        metrics: {
          'best_tok_s': maxOf(tokS) ?? 0,
          'median_tok_s': median(tokS) ?? 0,
          'best_rtf': maxOf(rtf) ?? 0,
          'median_rtf': median(rtf) ?? 0,
        },
        perRun: {'tok_s': tokS, 'rtf': rtf},
      ));
      setState(() {
        _statsLine = 'tok/s median ${(median(tokS) ?? 0).toStringAsFixed(1)} - '
            'rtf median ${(median(rtf) ?? 0).toStringAsFixed(2)}';
        _status = 'done';
      });
    } catch (e) {
      setState(() => _status = 'error: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  // --------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final ready = _controller.modelReady;
    return BenchScaffold(
      title: 'TTS bench',
      children: [
        Row(children: [
          const Text('Voice:'),
          const SizedBox(width: 12),
          Expanded(
            child: ModelChips<String>(
              models: _controller.availableVoices,
              selected: _controller.selectedVoice,
              label: (v) => v,
              enabled: ready && !_running,
              onSelected: (v) => _controller.switchVoice(v),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _textCtl,
          enabled: !_running,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Text to speak',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        StepperTile(
          label: 'runs',
          value: _runs,
          min: 1,
          max: 10,
          step: 1,
          enabled: !_running,
          onChanged: (v) => setState(() => _runs = v),
        ),
        if (!ready && _controller.loadPhase != null)
          LoadProgress(
            phase: _controller.loadPhase!,
            fraction: _controller.downloadProgress,
          ),
        const SizedBox(height: 12),
        ActionRow(
          running: _running,
          generateLabel: 'Synthesize',
          onGenerate: _synthesize,
          onBenchmark: _benchmark,
        ),
        const SizedBox(height: 12),
        StatusLine(text: _statsLine.isEmpty ? _status : _statsLine),
      ],
    );
  }
}

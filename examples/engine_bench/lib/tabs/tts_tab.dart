import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

import '../backend/bench_session.dart';
import '../backend/load_state.dart';
import '../backend/sdk_host.dart';
import '../widgets/bench_widgets.dart';

// ----------------------------------------------------------------------
// TtsTab — NeuTTS nano-multilingual streaming synth + benchmark
// ----------------------------------------------------------------------
// Synthesize streams audio through the SDK's audio player and reports
// time-to-first-audio / RTF / tok/s; Benchmark runs N silent synths and
// records the medians. The voice rides on each request, so switching
// it needs no reload.
const _ttsEnginesPath = String.fromEnvironment(
  'TTS_ENGINE_PATH',
  defaultValue: 'TheStageAI/neutts-nano-multilingual',
);
const _ttsRevision = String.fromEnvironment(
  'TTS_REVISION',
  defaultValue: '',
);

/// Shown before the model loads; the loaded bundle's own `voices`
/// replace it.
const _fallbackVoices = ['dave', 'bril', 'jo', 'paul'];

class TtsTab extends StatefulWidget {
  const TtsTab({super.key});

  @override
  State<TtsTab> createState() => _TtsTabState();
}

class _TtsTabState extends State<TtsTab> {
  static const _modelName = 'bench_tts';
  static const _sampleRate = 24000;

  final _player = TSAudioPlayer(sampleRate: _sampleRate);
  final _textCtl = TextEditingController(
    text: 'Hello! This is a test of the new text to speech model.',
  );

  bool _loaded = false;
  List<String> _voices = _fallbackVoices;
  String _voice = _fallbackVoices.first;
  int _runs = 3;
  bool _running = false;
  String _status = 'tap Synthesize';
  String _statsLine = '';
  String? _loadPhase;
  double? _loadFraction;
  StreamSubscription<Map<String, dynamic>>? _progressSub;

  @override
  void dispose() {
    _progressSub?.cancel();
    _player.stop();
    _textCtl.dispose();
    if (_loaded) {
      TheStageFlutterSDK.stop_model(model_name: _modelName)
          .catchError((Object _) => <String, dynamic>{});
    }
    super.dispose();
  }

  Future<void> _ensureReady() async {
    if (_loaded) return;
    await SdkHost.instance.ensureInitialized();
    _progressSub = TheStageFlutterSDK.on_progress.listen((e) {
      if (!mounted || !isProgressFor(e, _modelName)) return;
      setState(() {
        _loadPhase = e['phase'] as String?;
        _loadFraction = (e['progress'] as num?)?.toDouble();
      });
    });
    try {
      final status = await TheStageFlutterSDK.start_model(
        model_name: _modelName,
        engines_path: _ttsEnginesPath,
        model_type: 'neutts',
        revision: _ttsRevision,
        config: {'voice_id': _voice},
      );
      _loaded = true;
      final voices =
          voicesFromStatus(status, fallback: _fallbackVoices);
      if (mounted) {
        setState(() {
          _voices = voices;
          if (!voices.contains(_voice)) _voice = voices.first;
        });
      }
    } finally {
      await _progressSub?.cancel();
      _progressSub = null;
      if (mounted) setState(() => _loadPhase = null);
    }
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
      if (_player.isPlaying) await _player.stop();
      await _player.start();
      final sw = Stopwatch()..start();
      double? firstAudioS;
      var audioSeconds = 0.0;
      var totalSeconds = 0.0;
      var tps = 0.0;
      final stream = TheStageFlutterSDK.infer_stream(
        model_name: _modelName,
        input_json: {'text': text, 'voice_id': _voice},
      );
      await for (final chunk in stream) {
        final error = chunk['error'];
        if (error != null) throw StateError('$error');
        final audio = chunk['audio'] as Float32List?;
        final sr = (chunk['sample_rate'] as num?)?.toInt() ?? _sampleRate;
        if (audio != null && audio.isNotEmpty) {
          firstAudioS ??= sw.elapsedMicroseconds / 1e6;
          audioSeconds += audio.length / sr;
          _player.enqueue(audio);
        }
        if (chunk['is_final'] == true) {
          totalSeconds = (chunk['total_seconds'] as num?)?.toDouble() ?? 0;
          tps = (chunk['tokens_per_second'] as num?)?.toDouble() ?? 0;
        }
      }
      final rtf = totalSeconds > 0 ? audioSeconds / totalSeconds : 0.0;
      if (mounted) {
        setState(() {
          _statsLine = '${audioSeconds.toStringAsFixed(2)}s audio - '
              'TTFA ${((firstAudioS ?? 0) * 1000).toStringAsFixed(0)} ms - '
              'rtf ${rtf.toStringAsFixed(2)} - '
              '${tps.toStringAsFixed(1)} tok/s';
          _status = 'playing...';
        });
      }
      // Keep the buttons disabled until the audio has played out.
      await _player.drain();
      if (mounted) setState(() => _status = 'done');
    } catch (e) {
      if (mounted) setState(() => _status = 'error: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  // --------------------------------------------------------------------
  // Benchmark (N silent synths — no playback, records medians)
  // --------------------------------------------------------------------
  Future<Map<String, double>> _runSilent(String text) async {
    final stream = TheStageFlutterSDK.infer_stream(
      model_name: _modelName,
      input_json: {'text': text, 'voice_id': _voice},
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
        voice: _voice,
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
    return BenchScaffold(
      title: 'TTS bench',
      children: [
        Row(children: [
          const Text('Voice:'),
          const SizedBox(width: 12),
          Expanded(
            child: ModelChips<String>(
              models: _voices,
              selected: _voice,
              label: (v) => v,
              enabled: !_running,
              onSelected: (v) => setState(() => _voice = v),
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
        if (_loadPhase != null)
          LoadProgress(phase: _loadPhase!, fraction: _loadFraction),
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

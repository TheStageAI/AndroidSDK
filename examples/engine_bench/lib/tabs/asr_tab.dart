import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

import '../backend/bench_session.dart';
import '../backend/sdk_host.dart';
import '../widgets/bench_widgets.dart';

// ----------------------------------------------------------------------
// AsrTab — Whisper turbo record-and-transcribe + benchmark
// ----------------------------------------------------------------------
// Android ASR = Whisper only (the iOS EngineBench's Qwen3-ASR row has no
// Android counterpart, so it is dropped). There is no bundled fixture, so
// Benchmark replays the LAST recorded clip warmup + N times and records
// the medians (rtfx / decode tok/s / encoder ms).
const _asrEnginesPath = String.fromEnvironment(
  'WHISPER_ENGINE_PATH',
  defaultValue: 'TheStageAI/thewhisper-large-v3-turbo',
);
const _asrRevision = String.fromEnvironment(
  'WHISPER_REVISION',
  defaultValue: 'android',
);
const _sampleRate = 16000;

class AsrTab extends StatefulWidget {
  const AsrTab({super.key});

  @override
  State<AsrTab> createState() => _AsrTabState();
}

class _AsrTabState extends State<AsrTab> {
  static const _modelName = 'bench_whisper';
  static const _maxRecordSeconds = 60;

  final _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioSub;
  final List<double> _captured = [];
  List<double> _lastClip = [];

  int _runs = 3;
  bool _loaded = false;
  bool _running = false;
  bool _recording = false;
  String _status = 'tap Record';
  String _statsLine = '';
  String _transcript = '';
  String? _loadPhase;
  double _loadFraction = 0;
  StreamSubscription<Map<String, dynamic>>? _progressSub;

  @override
  void dispose() {
    _audioSub?.cancel();
    _progressSub?.cancel();
    _recorder.dispose();
    _stopModel();
    super.dispose();
  }

  Future<void> _stopModel() async {
    try {
      await TheStageFlutterSDK.stop_model(model_name: _modelName);
    } catch (_) {}
  }

  Future<void> _ensureModel() async {
    if (_loaded) return;
    await SdkHost.instance.ensureInitialized();
    _progressSub = TheStageFlutterSDK.on_progress.listen((e) {
      if (!mounted) return;
      setState(() {
        _loadPhase = e['phase'] as String?;
        _loadFraction = (e['progress'] as num?)?.toDouble() ?? 0;
      });
    });
    try {
      await TheStageFlutterSDK.start_model(
        model_type: 'whisper',
        model_name: _modelName,
        engines_path: _asrEnginesPath,
        revision: _asrRevision,
        device: 'npu',
      );
      _loaded = true;
    } finally {
      await _progressSub?.cancel();
      _progressSub = null;
      if (mounted) setState(() => _loadPhase = null);
    }
  }

  // --------------------------------------------------------------------
  // Record
  // --------------------------------------------------------------------
  static List<double> _pcm16ToFloat(Uint8List bytes) {
    final n = bytes.lengthInBytes ~/ 2;
    if (n == 0) return const [];
    final view = ByteData.sublistView(bytes, 0, n * 2);
    final out = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      await _stopAndTranscribe();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (_running) return;
    if (!await _recorder.hasPermission()) {
      setState(() => _status = 'mic permission denied');
      return;
    }
    setState(() {
      _transcript = '';
      _statsLine = '';
      _captured.clear();
      _recording = true;
      _status = 'recording... tap Stop';
    });
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
        androidConfig: AndroidRecordConfig(
          audioSource: AndroidAudioSource.voiceRecognition,
        ),
      ),
    );
    _audioSub = stream.listen((bytes) {
      final samples = _pcm16ToFloat(bytes);
      if (samples.isEmpty) return;
      _captured.addAll(samples);
      final secs = _captured.length / _sampleRate;
      if (mounted) {
        setState(() =>
            _status = 'recording... ${secs.toStringAsFixed(1)}s (tap Stop)');
      }
      if (_captured.length > _maxRecordSeconds * _sampleRate) {
        _stopAndTranscribe();
      }
    });
  }

  Future<void> _stopAndTranscribe() async {
    if (!_recording) return;
    setState(() => _recording = false);
    await _audioSub?.cancel();
    _audioSub = null;
    try {
      await _recorder.stop();
    } catch (_) {}

    final audio = List<double>.of(_captured);
    _captured.clear();
    if (audio.length < 1600) {
      setState(() => _status = 'recording too short');
      return;
    }
    _lastClip = audio;
    setState(() {
      _running = true;
      _status = 'loading Whisper...';
    });
    try {
      await _ensureModel();
      setState(() => _status = 'transcribing...');
      final out = await TheStageFlutterSDK.infer(
        model_name: _modelName,
        input_json: {
          'audio': audio,
          'language': 'en',
          'max_new_tokens': 128,
        },
      );
      final first = out.isNotEmpty ? out.first : const <String, dynamic>{};
      final m = _metricsFrom(first, audio.length / _sampleRate);
      setState(() {
        _transcript = (first['transcription'] as String?)?.trim().isNotEmpty ==
                true
            ? (first['transcription'] as String).trim()
            : '(no speech)';
        _statsLine = _fmtMetrics(m);
        _status = 'done';
      });
    } catch (e) {
      setState(() => _status = 'error: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  // --------------------------------------------------------------------
  // Benchmark (replay last clip)
  // --------------------------------------------------------------------
  Map<String, double> _metricsFrom(
    Map<String, dynamic> r,
    double audioSeconds,
  ) {
    final total = (r['total_seconds'] as num?)?.toDouble() ?? 0;
    final enc = (r['encoder_seconds'] as num?)?.toDouble() ?? 0;
    final tps = (r['tokens_per_second'] as num?)?.toDouble() ?? 0;
    final rtfx = total > 0 ? audioSeconds / total : 0.0;
    return {
      'rtfx': rtfx,
      'tok_s': tps,
      'encode_ms': enc * 1000,
    };
  }

  String _fmtMetrics(Map<String, double> m) {
    return 'rtfx ${m['rtfx']!.toStringAsFixed(2)} - '
        '${m['tok_s']!.toStringAsFixed(1)} tok/s - '
        'enc ${m['encode_ms']!.toStringAsFixed(0)} ms';
  }

  Future<void> _benchmark() async {
    if (_running || _recording) return;
    if (_lastClip.isEmpty) {
      setState(() => _status = 'record a clip first, then Benchmark');
      return;
    }
    final n = _runs < 1 ? 1 : _runs;
    final audio = _lastClip;
    final audioSeconds = audio.length / _sampleRate;
    setState(() {
      _running = true;
      _statsLine = '';
      _status = 'preparing...';
    });
    try {
      await _ensureModel();
      setState(() => _status = 'warmup...');
      await TheStageFlutterSDK.infer(
        model_name: _modelName,
        input_json: {'audio': audio, 'language': 'en', 'max_new_tokens': 128},
      );
      final rtfx = <double>[];
      final tokS = <double>[];
      final enc = <double>[];
      for (var k = 0; k < n; k++) {
        setState(() => _status = 'run ${k + 1}/$n...');
        final out = await TheStageFlutterSDK.infer(
          model_name: _modelName,
          input_json: {
            'audio': audio,
            'language': 'en',
            'max_new_tokens': 128,
          },
        );
        final first =
            out.isNotEmpty ? out.first : const <String, dynamic>{};
        final m = _metricsFrom(first, audioSeconds);
        rtfx.add(m['rtfx']!);
        tokS.add(m['tok_s']!);
        enc.add(m['encode_ms']!);
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      BenchSession.instance.add(BenchRecord(
        kind: 'asr',
        model: 'Whisper turbo',
        runs: n,
        metrics: {
          'best_rtfx': maxOf(rtfx) ?? 0,
          'median_rtfx': median(rtfx) ?? 0,
          'median_tok_s': median(tokS) ?? 0,
          'median_encode_ms': median(enc) ?? 0,
        },
        perRun: {'rtfx': rtfx, 'tok_s': tokS, 'encode_ms': enc},
      ));
      setState(() {
        _statsLine = 'rtfx median ${(median(rtfx) ?? 0).toStringAsFixed(2)} - '
            'dec ${(median(tokS) ?? 0).toStringAsFixed(1)} tok/s - '
            'enc ${(median(enc) ?? 0).toStringAsFixed(0)} ms';
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
      title: 'ASR bench',
      children: [
        StepperTile(
          label: 'runs',
          value: _runs,
          min: 1,
          max: 10,
          step: 1,
          enabled: !_running && !_recording,
          onChanged: (v) => setState(() => _runs = v),
        ),
        if (_loadPhase != null)
          LoadProgress(phase: _loadPhase!, fraction: _loadFraction),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _running ? null : _toggleRecord,
              icon: Icon(_recording ? Icons.stop : Icons.mic),
              label: Text(_recording ? 'Stop' : 'Record'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.tonal(
              onPressed:
                  (_running || _recording) ? null : _benchmark,
              child: Text(_running ? '...' : 'Benchmark'),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (_transcript.isNotEmpty) OutputBox(text: _transcript),
        const SizedBox(height: 8),
        StatusLine(text: _statsLine.isEmpty ? _status : _statsLine),
      ],
    );
  }
}

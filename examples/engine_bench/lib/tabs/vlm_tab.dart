import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

import '../backend/bench_session.dart';
import '../backend/sdk_host.dart';
import '../widgets/bench_widgets.dart';

// ----------------------------------------------------------------------
// VlmTab — LFM2.5-VL caption (streaming) + benchmark
// ----------------------------------------------------------------------
// The whole stack (vision -> projector -> prompt -> Genie LLM) runs
// on-device. Pick an image (gallery / camera), then Generate (streaming,
// honest TTFT) or Benchmark (warmup + N quiet runs, records tok/s medians).
const _vlmEnginesPath = String.fromEnvironment(
  'LFM2_VL_ENGINES_PATH',
  defaultValue: 'TheStageAI/LFM2.5-VL-450M',
);
const _vlmRevision = String.fromEnvironment(
  'LFM2_VL_REVISION',
  defaultValue: 'android',
);

class VlmTab extends StatefulWidget {
  const VlmTab({super.key});

  @override
  State<VlmTab> createState() => _VlmTabState();
}

class _VlmTabState extends State<VlmTab> {
  static const _modelName = 'bench_vlm';
  static const _preset = 'medium';
  static const _warmupRuns = 1;

  final _picker = ImagePicker();
  final _promptCtl =
      TextEditingController(text: 'Describe this image briefly.');
  String? _imagePath;
  int _maxNew = 64;
  int _runs = 5;

  bool _loaded = false;
  bool _running = false;
  String _status = 'pick an image, then Generate';
  String _statsLine = '';
  String _output = '';
  String? _loadPhase;
  double _loadFraction = 0;
  StreamSubscription<Map<String, dynamic>>? _progressSub;

  @override
  void dispose() {
    _promptCtl.dispose();
    _progressSub?.cancel();
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
        model_type: 'lfm2-vl',
        model_name: _modelName,
        engines_path: _vlmEnginesPath,
        revision: _vlmRevision,
        device: 'npu',
      );
      _loaded = true;
    } finally {
      await _progressSub?.cancel();
      _progressSub = null;
      if (mounted) setState(() => _loadPhase = null);
    }
  }

  Future<void> _pick(ImageSource source) async {
    if (_running) return;
    try {
      final file = await _picker.pickImage(source: source, maxWidth: 1280);
      if (file == null) return;
      setState(() {
        _imagePath = file.path;
        _status = 'image ready - tap Generate or Benchmark';
      });
    } catch (e) {
      setState(() => _status = 'pick error: $e');
    }
  }

  // --------------------------------------------------------------------
  // Generate (streaming)
  // --------------------------------------------------------------------
  Future<void> _generate() async {
    if (_running) return;
    final path = _imagePath;
    if (path == null) {
      setState(() => _status = 'pick an image first');
      return;
    }
    setState(() {
      _running = true;
      _output = '';
      _statsLine = '';
      _status = 'loading...';
    });
    try {
      await _ensureModel();
      setState(() => _status = 'encoding...');
      final stream = TheStageFlutterSDK.infer_stream(
        model_name: _modelName,
        input_json: {
          'inputs': {
            'image': path,
            'prompt': _promptCtl.text.trim(),
            'preset': _preset,
            'max_new_tokens': _maxNew,
          },
        },
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
            _statsLine = '$tokens tok - decode ${tps.toStringAsFixed(1)} tok/s'
                ' - TTFT ${ttftMs.toStringAsFixed(0)} ms';
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
  // Benchmark (warmup + N quiet runs)
  // --------------------------------------------------------------------
  Future<Map<String, double>> _runSilent(String path, String prompt) async {
    final sw = Stopwatch()..start();
    final stream = TheStageFlutterSDK.infer_stream(
      model_name: _modelName,
      input_json: {
        'inputs': {
          'image': path,
          'prompt': prompt,
          'preset': _preset,
          'max_new_tokens': _maxNew,
        },
      },
    );
    var tps = 0.0;
    var ttftMs = 0.0;
    var tokens = 0.0;
    await for (final chunk in stream) {
      if (chunk['is_final'] == true) {
        tps = (chunk['tokens_per_second'] as num?)?.toDouble() ?? 0;
        ttftMs =
            ((chunk['time_to_first_token'] as num?)?.toDouble() ?? 0) * 1000;
        tokens = (chunk['generated_tokens'] as num?)?.toDouble() ?? 0;
      }
    }
    sw.stop();
    return {
      'tok_s': tps,
      'ttft_ms': ttftMs,
      'tokens': tokens,
      'total_ms': sw.elapsedMilliseconds.toDouble(),
    };
  }

  Future<void> _benchmark() async {
    if (_running) return;
    final path = _imagePath;
    if (path == null) {
      setState(() => _status = 'pick an image first');
      return;
    }
    final prompt = _promptCtl.text.trim();
    final n = _runs < 1 ? 1 : _runs;
    setState(() {
      _running = true;
      _output = '';
      _statsLine = '';
      _status = 'warmup + $n quiet runs...';
    });
    try {
      await _ensureModel();
      for (var w = 0; w < _warmupRuns; w++) {
        await _runSilent(path, prompt);
      }
      final tokS = <double>[];
      final ttftMs = <double>[];
      final totalMs = <double>[];
      var tokens = 0;
      for (var k = 0; k < n; k++) {
        setState(() => _status = 'run ${k + 1}/$n...');
        final r = await _runSilent(path, prompt);
        tokS.add(r['tok_s']!);
        ttftMs.add(r['ttft_ms']!);
        totalMs.add(r['total_ms']!);
        tokens = r['tokens']!.toInt();
      }
      BenchSession.instance.add(BenchRecord(
        kind: 'vlm',
        model: 'LFM2.5-VL 450M',
        runs: n,
        prompt: prompt,
        maxNewTokens: _maxNew,
        metrics: {
          'best_tok_s': maxOf(tokS) ?? 0,
          'median_tok_s': median(tokS) ?? 0,
          'mean_tok_s': mean(tokS) ?? 0,
          'median_ttft_ms': median(ttftMs) ?? 0,
          'median_total_ms': median(totalMs) ?? 0,
          'tokens': tokens.toDouble(),
        },
        perRun: {'tok_s': tokS, 'ttft_ms': ttftMs, 'total_ms': totalMs},
      ));
      setState(() {
        _statsLine = 'best ${(maxOf(tokS) ?? 0).toStringAsFixed(1)} / '
            'median ${(median(tokS) ?? 0).toStringAsFixed(1)} tok/s - '
            'ttft ${(median(ttftMs) ?? 0).toStringAsFixed(0)} ms';
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
      title: 'VLM bench',
      children: [
        Row(children: [
          _preview(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      _running ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo),
                  label: const Text('Gallery'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed:
                      _running ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                ),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _promptCtl,
          enabled: !_running,
          minLines: 1,
          maxLines: 3,
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
              max: 256,
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

  Widget _preview() {
    final path = _imagePath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 84,
        height: 84,
        child: path == null
            ? Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.photo, size: 32),
              )
            : Image.file(File(path), fit: BoxFit.cover),
      ),
    );
  }
}

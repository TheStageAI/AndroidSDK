import 'dart:async';

import 'package:thestage_android_sdk/thestage_android_sdk.dart';

/// Who owns `start_model` / `stop_model` for the VLM handle.
enum VlmLifecycle {
  /// Node starts/stops the model in [onStart] / [onStop].
  owned,

  /// Host [ModelRoster] owns residency; node only infers.
  external,
}

/// App-local example node: submit an image → caption stream + port.
///
/// Inference takes the image as a file **path**
/// (`{'prompt': ..., 'image': path}`). [modelType] is the VLM family
/// (`'lfm2-vl'` or `'gemma4-vl'`).
///
/// The node only drains in quiet agent states (`runWhen`) so a VLM burst
/// never competes with the LLM / TTS during an active turn.
class VLMCaptionNode extends TSAgentNode {
  VLMCaptionNode({
    this.id = 'vlm',
    // Quiet states only — never drain during thinking / speaking.
    this.runWhen = const ['idle', 'sleeping', 'listening'],
    required this.enginesPath,
    this.modelType = 'lfm2-vl',
    this.prompt = 'Describe briefly for the voice assistant.',
    // Empty takes the best bundle for this phone.
    this.device = '',
    // Empty resolves the repo's SDK-pinned commit.
    this.revision = '',
    this.lifecycle = VlmLifecycle.external,
  });

  @override
  final String id;

  @override
  final List<String> runWhen;

  final String enginesPath;
  final String modelType;
  final String prompt;
  final String device;
  final String revision;
  final VlmLifecycle lifecycle;

  bool _modelReady = false;
  final _pending = <String>[];
  final _captions = StreamController<String>.broadcast();
  AgentNodeContext? _ctx;

  Stream<String> get captions => _captions.stream;

  /// Mark the model ready when [lifecycle] is [VlmLifecycle.external]
  /// (the host [ModelRoster] started / stopped the VLM handle).
  void markReady({required bool ready}) {
    _modelReady = ready;
  }

  @override
  Future<void> onStart(AgentNodeContext context) async {
    _ctx = context;
    if (lifecycle == VlmLifecycle.owned) {
      await TheStageFlutterSDK.start_model(
        model_name: id,
        engines_path: enginesPath,
        model_type: modelType,
        device: device,
        revision: revision,
      );
      _modelReady = true;
    }
  }

  @override
  Future<void> onStop() async {
    if (lifecycle == VlmLifecycle.owned && _modelReady) {
      await TheStageFlutterSDK.stop_model(model_name: id);
    }
    _modelReady = false;
  }

  @override
  Future<void> onState(AgentNodeContext context, String state) async {
    _ctx = context;
    // Auto-drain when the agent re-enters a quiet (gate-open) state.
    if (context.isGateOpen) await _drain();
  }

  /// Queue an image (by file path) for captioning. The host guarantees a
  /// quiet agent state before calling, so the drain does not re-check the
  /// gate here (the auto-drain in [onState] still does).
  Future<void> submitImage({required String path}) async {
    _pending.add(path);
    if (_modelReady && _ctx != null) await _drain();
  }

  Future<void> _drain() async {
    final ctx = _ctx;
    if (ctx == null || !_modelReady) return;
    final batch = List<String>.from(_pending);
    _pending.clear();
    for (final path in batch) {
      if (_captions.isClosed) return;
      final results = await TheStageFlutterSDK.infer(
        model_name: id,
        input_json: {
          'prompt': prompt,
          'image': path,
        },
      );
      final caption = results.isEmpty
          ? ''
          : (results.first['text']?.toString() ??
              results.first['caption']?.toString() ??
              '');
      // The node may have been disposed while the inference ran.
      if (caption.isNotEmpty && !_captions.isClosed) {
        _captions.add(caption);
        // Local port name → bus `vlm.caption`.
        ctx.sendPort('caption', caption);
      }
    }
  }

  void dispose() {
    _captions.close();
  }
}

import 'dart:async';

import 'package:flutter/services.dart';

import 'agent_node.dart';
import 'method_channels.dart';

// ---------------------------------------------------------------------------
// TheStageAgentState
// ---------------------------------------------------------------------------
enum TheStageAgentState {
  idle,
  loading,
  sleeping,
  listening,
  thinking,
  speaking;

  static TheStageAgentState fromString(String value) {
    return TheStageAgentState.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TheStageAgentState.idle,
    );
  }
}

// ---------------------------------------------------------------------------
// TheStageVoiceAgentFlutter
// ---------------------------------------------------------------------------
/// Flutter bridge for the native `TheStageVoiceAgent`.
///
/// All orchestration runs natively — this class forwards lifecycle
/// commands and emits events for the UI to consume.
///
/// Usage:
/// ```dart
/// final agent = TheStageVoiceAgentFlutter();
/// agent.events.listen((event) => handleEvent(event));
/// await agent.start(config: { ... });
/// await agent.stop();
/// ```
class TheStageVoiceAgentFlutter {
  static const MethodChannel _channel = MethodChannel(MethodChannels.main);
  static const MethodChannel _nodesChannel = MethodChannel(
    MethodChannels.voiceAgentNodes,
  );
  static const EventChannel _eventChannel = EventChannel(
    MethodChannels.voiceAgentEvents,
  );
  static const EventChannel _llmDeltasChannel = EventChannel(
    MethodChannels.voiceAgentLLMDeltas,
  );
  static const EventChannel _transcriptsChannel = EventChannel(
    MethodChannels.voiceAgentTranscripts,
  );
  static const EventChannel _vadProbsChannel = EventChannel(
    MethodChannels.voiceAgentVADProbabilities,
  );
  static const EventChannel _portsChannel = EventChannel(
    MethodChannels.voiceAgentPorts,
  );

  StreamSubscription? _eventSub;
  StreamSubscription? _portSub;
  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _portController =
      StreamController<Map<String, dynamic>>.broadcast();
  VoiceAgentNodeDispatcher? _nodeDispatcher;

  // Lazy `broadcast` views over the typed EventChannels so multiple
  // widgets can listen at once. The native handler creates / tears the
  // tap down based on Dart subscription state, so leaving these unused
  // costs nothing.
  late final Stream<String> _llmDeltas = _llmDeltasChannel
      .receiveBroadcastStream()
      .map((e) => e.toString());
  late final Stream<String> _transcripts = _transcriptsChannel
      .receiveBroadcastStream()
      .map((e) => e.toString());
  late final Stream<double> _vadProbabilities = _vadProbsChannel
      .receiveBroadcastStream()
      .map((e) => (e as num).toDouble());

  TheStageAgentState _state = TheStageAgentState.idle;

  // -------------------------------------------------------------------------
  // Public Getters
  // -------------------------------------------------------------------------

  /// Current agent state.
  TheStageAgentState get state => _state;

  /// Aggregate stream of agent events (state changes, transcripts,
  /// deltas, errors, ...).
  Stream<Map<String, dynamic>> get events => _controller.stream;

  /// Stream of LLM token deltas for the current reply.
  Stream<String> get llmDeltas => _llmDeltas;

  /// Stream of finalized user transcripts, one per turn.
  Stream<String> get transcripts => _transcripts;

  /// Per-frame VAD probability ([0.0, 1.0]).
  Stream<double> get vadProbabilities => _vadProbabilities;

  /// Multiplexed stream of `{port, value}` events from the native
  /// `AgentPortRegistry` (built-in aliases plus custom node ports).
  Stream<Map<String, dynamic>> get portEvents => _portController.stream;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// Start the voice agent with the given configuration.
  ///
  /// Config keys map 1:1 to the native `TheStageAgentConfig` fields:
  ///
  /// Models (HF repo IDs or local paths):
  /// - `vad`, `stt`, `tts`: String — model bundles
  /// - `tts_voice`: String — voice preset id
  /// - `wake_word`: String? — wake-word bundle (null = disabled)
  ///
  /// LLM:
  /// - `llm_provider`: 'local' | 'openai_compatible'
  /// - `llm_model`: String (model name/path)
  /// - `llm_endpoint`: String? (URL for cloud)
  /// - `llm_api_key`: String? (for cloud)
  /// - `system_prompt`: String, `max_tokens`: int, `temperature`: double
  ///
  /// Compute device routing (default `"npu"` everywhere):
  /// - `vad_device`, `stt_device`, `tts_device`, `ww_device`: String
  /// - `stt_devices`, `tts_devices`: Map<String, String>? — per-module
  /// - `stt_revision`, `tts_revision`: String — HF branch/tag
  ///
  /// VAD / endpointing:
  /// - `vad_threshold`: double, `silence_timeout_ms`: int,
  ///   `pre_roll_ms`: int, `speculative_whisper`: bool
  ///
  /// Interruptions / AEC:
  /// - `allow_interruptions`: bool
  /// - `interrupt_mode`: 'none' | 'speech_only' | 'wake_word'
  /// - `interrupt_min_speech_ms`: int, `aec_enabled`: bool
  /// - `stt_language`: String
  ///
  /// Speaker-id gating:
  /// - `speaker_id`: String — speaker-embedding bundle
  /// - `speaker_id_device`: String, `speaker_similarity_threshold`: double
  /// - `enrolled_speaker_embedding`: List<double>? — reference embedding
  ///
  /// [extraNodes] appends custom Dart nodes to the native graph; their
  /// descriptors are merged into `config['extra_nodes']`.
  Future<void> start({
    required Map<String, dynamic> config,
    List<TheStageAgentNode> extraNodes = const [],
  }) async {
    _startListeningEvents();
    _startListeningPorts();

    final merged = Map<String, dynamic>.from(config);
    if (extraNodes.isNotEmpty) {
      merged['extra_nodes'] = extraNodes.map((n) => n.toDescriptor()).toList();
    }

    _nodeDispatcher?.dispose();
    _nodeDispatcher = VoiceAgentNodeDispatcher(
      nodesChannel: _nodesChannel,
      portEvents: portEvents,
      sendNodePort: _sendNodePort,
      publishNodeEvent: _publishNodeEvent,
    )..registerNodes(extraNodes)
      ..installHandler();

    await _channel.invokeMethod(MethodRoute.voiceAgentStart, merged);
  }

  /// Stop the voice agent and release all resources.
  Future<void> stop() async {
    await _channel.invokeMethod(MethodRoute.voiceAgentStop);
    _nodeDispatcher?.dispose();
    _nodeDispatcher = null;
    _state = TheStageAgentState.idle;
  }

  /// Interrupt the current response (cancel LLM + TTS).
  Future<void> interrupt() async {
    await _channel.invokeMethod(MethodRoute.voiceAgentInterrupt);
  }

  /// Open the mic and begin listening after a deferred-mic
  /// `start(config: {'auto_listen': false})` — call once any heavy
  /// deferred local models (e.g. an on-device LLM) are ready.
  /// Idempotent (no-op if already listening).
  Future<void> beginListening() async {
    await _channel.invokeMethod(MethodRoute.voiceAgentBeginListening);
  }

  /// Speak text directly, bypassing LLM.
  Future<void> say(String text) async {
    await _channel.invokeMethod(MethodRoute.voiceAgentSay, {'text': text});
  }

  /// Inject a typed user turn, bypassing the mic and ASR. Drives the
  /// same LLM -> TTS path as a spoken turn. No-op if the agent has no
  /// LLM responder (transcription-only).
  Future<void> sendRequest(String text) async {
    await _channel.invokeMethod(
      MethodRoute.voiceAgentSendRequest,
      {'text': text},
    );
  }

  /// Change the TTS voice at runtime.
  Future<void> setVoice(String voice) async {
    await _channel.invokeMethod(
      MethodRoute.voiceAgentSetVoice,
      {'voice': voice},
    );
  }

  /// Clear conversation history.
  Future<void> clearHistory() async {
    await _channel.invokeMethod(MethodRoute.voiceAgentClearHistory);
  }

  /// Enroll or clear the speaker embedding used by speaker-id gating.
  /// Pass `embedding: null` to clear enrollment. `audioPath` enrollment
  /// is not supported yet (embedding-only, same as iOS).
  Future<void> enrollSpeaker({
    List<double>? embedding,
    String? audioPath,
  }) async {
    if (audioPath != null) {
      throw UnsupportedError(
        'audioPath enrollment is not supported yet; pass embedding instead.',
      );
    }
    await _channel.invokeMethod(MethodRoute.voiceAgentEnrollSpeaker, {
      'embedding': embedding,
    });
  }

  /// Subscribe to a named agent port (`llm.delta`, `vad.probability`, or
  /// a custom node port such as `my_node.caption`).
  Stream<dynamic> subscribePort(String name) {
    return portEvents
        .where((event) => event['port'] == name)
        .map((event) => event['value']);
  }

  /// Hot-update interrupt-related knobs on a running agent. Any `null`
  /// argument is left untouched on the native side.
  ///
  /// - `interruptMinSpeechMs`: sustained speech (ms) to fire barge-in.
  /// - `interruptMinPlaybackMs`: AEC-converge grace at TTS-turn start.
  /// - `interruptMode`: `'none'` | `'speech_only'` | `'wake_word'`.
  Future<void> updateInterruptConfig({
    int? interruptMinSpeechMs,
    int? interruptMinPlaybackMs,
    String? interruptMode,
    int? interruptOnsetMs,
    double? interruptThreshold,
  }) async {
    final args = <String, dynamic>{};
    if (interruptMinSpeechMs != null) {
      args['interrupt_min_speech_ms'] = interruptMinSpeechMs;
    }
    if (interruptMinPlaybackMs != null) {
      args['interrupt_min_playback_ms'] = interruptMinPlaybackMs;
    }
    if (interruptMode != null) {
      args['interrupt_mode'] = interruptMode;
    }
    if (interruptOnsetMs != null) {
      args['interrupt_onset_ms'] = interruptOnsetMs;
    }
    if (interruptThreshold != null) {
      args['interrupt_threshold'] = interruptThreshold;
    }
    if (args.isEmpty) return;
    await _channel.invokeMethod(
      MethodRoute.voiceAgentUpdateInterruptConfig,
      args,
    );
  }

  /// Dispose resources. Call when done with the agent.
  void dispose() {
    _eventSub?.cancel();
    _portSub?.cancel();
    _nodeDispatcher?.dispose();
    _controller.close();
    _portController.close();
  }

  // -------------------------------------------------------------------------
  // Private
  // -------------------------------------------------------------------------

  Future<void> _sendNodePort(
    String nodeId,
    String port,
    String value,
  ) async {
    await _channel.invokeMethod(MethodRoute.voiceAgentSendNodePort, {
      'node_id': nodeId,
      'port': port,
      'value': value,
    });
  }

  Future<void> _publishNodeEvent(
    String nodeId,
    Map<String, dynamic> event,
  ) async {
    await _channel.invokeMethod(MethodRoute.voiceAgentPublishNodeEvent, {
      'node_id': nodeId,
      'event': event,
    });
  }

  void _startListeningPorts() {
    _portSub?.cancel();
    _portSub = _portsChannel.receiveBroadcastStream().listen(
      (event) {
        final map = (event as Map<Object?, Object?>).map(
          (k, v) => MapEntry(k.toString(), v),
        );
        _portController.add(map);
      },
      onError: (e) => _portController.addError(e),
    );
  }

  void _startListeningEvents() {
    _eventSub?.cancel();
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        final map = (event as Map<Object?, Object?>).map(
          (k, v) => MapEntry(k.toString(), v),
        );

        if (map['kind'] == 'state_changed') {
          final stateStr = map['state']?.toString() ?? 'idle';
          _state = TheStageAgentState.fromString(stateStr);
        }

        _controller.add(map);
      },
      onError: (e) => _controller.addError(e),
    );
  }
}

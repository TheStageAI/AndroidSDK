import 'dart:async';

import 'package:flutter/services.dart';

import 'agent_node.dart';
import 'ts_agent_capabilities.dart';
import 'method_channels.dart';

// ---------------------------------------------------------------------------
// TSAgentState
// ---------------------------------------------------------------------------
/// Voice-agent state, as reported by `state_changed` events.
enum TSAgentState {
  idle,
  loading,
  sleeping,
  listening,
  thinking,

  /// The model called a tool and the agent is running it
  /// (`tool_started` .. `tool_ended`).
  tool_calling,
  speaking;

  static TSAgentState fromString(String value) {
    return TSAgentState.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TSAgentState.idle,
    );
  }
}

// ---------------------------------------------------------------------------
// TSVoiceAgent
// ---------------------------------------------------------------------------
/// Flutter bridge for the native `TheStageVoiceAgent`.
///
/// All orchestration runs natively — this class forwards lifecycle
/// commands and emits events for the UI to consume.
///
/// Usage:
/// ```dart
/// final agent = TSVoiceAgent();
/// agent.events.listen((event) => handleEvent(event));
/// final caps = await agent.start(config: { ... });
/// await agent.stop();
/// ```
class TSVoiceAgent {
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
  static const EventChannel _ttsLevelsChannel = EventChannel(
    MethodChannels.voiceAgentTTSLevels,
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
  late final Stream<double> _ttsLevels = _ttsLevelsChannel
      .receiveBroadcastStream()
      .map((e) => (e as num).toDouble());

  TSAgentState _state = TSAgentState.idle;

  // -------------------------------------------------------------------------
  // Public Getters
  // -------------------------------------------------------------------------

  /// Current agent state.
  TSAgentState get state => _state;

  /// Aggregate stream of agent events (state changes, transcripts,
  /// deltas, errors, ...). Each is a flat map with a `kind`; tool
  /// calls arrive as `tool_started` (`name`, `arguments`: a JSON
  /// object string) and `tool_ended` (`name`, `content`).
  Stream<Map<String, dynamic>> get events => _controller.stream;

  /// Stream of LLM token deltas for the current reply.
  Stream<String> get llm_deltas => _llmDeltas;

  /// Stream of finalized user transcripts, one per turn.
  Stream<String> get transcripts => _transcripts;

  /// Per-frame VAD probability ([0.0, 1.0]).
  Stream<double> get vad_probabilities => _vadProbabilities;

  /// Loudness of the assistant's speech as it plays ([0.0, 1.0]),
  /// about 30 values per second while speaking and a final 0.0 when
  /// playback ends or is interrupted. Drive an avatar's mouth or a
  /// speaking meter with it.
  Stream<double> get tts_levels => _ttsLevels;

  /// Multiplexed stream of `{port, value}` events from the native
  /// `AgentPortRegistry` (built-in aliases plus custom node ports).
  Stream<Map<String, dynamic>> get port_events => _portController.stream;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// What the running agent can do, as returned by the last [start]:
  ///
  /// - `listening` — mic + VAD are up and the mic is open (`false`
  ///   after an `auto_listen: false` start until [begin_listening]).
  /// - `transcribing` — speech recognition runs.
  /// - `responding` — a spoken turn reaches an LLM that answers.
  /// - `speaking` — TTS runs (replies and [say] are heard).
  /// - `reasons` — `Map<String, String>`, one entry per `false`
  ///   capability, keyed by its name.
  ///
  /// Empty before the first [start] and after a failed one;
  /// refreshed by [begin_listening] and [set_voice].
  Map<String, dynamic> capabilities = const {};

  /// Start the voice agent with the given configuration and return its
  /// [capabilities].
  ///
  /// Config keys map 1:1 to the native `TheStageAgentConfig` fields:
  ///
  /// Models (HF repo IDs or local paths):
  /// - `vad`, `stt`, `tts`: String — model bundles (no `tts` =
  ///   transcription-only)
  /// - `tts_voice`: String — voice id from the TTS bundle
  /// - `tts_voice_dir`: String? — a voice-pack folder holding
  ///   `voice.json`; wins over `tts_voice`
  /// - `tts_language`: String? — TTS language override (`'french'`)
  /// - `wake_word`: String? — wake-word bundle (null = disabled)
  ///
  /// LLM:
  /// - `llm_provider`: 'local' | 'openai_compatible'
  /// - `llm_model`: String (model name/path)
  /// - `llm_endpoint`: String? (URL for cloud)
  /// - `llm_api_key`: String? (for cloud)
  /// - `system_prompt`: String (default: the SDK's voice prompt),
  ///   `max_tokens`: int, `temperature`: double
  /// - `llm_tools`: 'voice' (default) | 'web' | 'phone' | 'none' —
  ///   built-in tools of the on-device LLM
  ///
  /// Compute device routing (default `''` everywhere = the best
  /// bundle the model publishes for this device; `'npu'` / `'cpu'`
  /// is a constraint, and the start fails if the model has no such
  /// bundle):
  /// - `vad_device`, `stt_device`, `tts_device`, `ww_device`,
  ///   `llm_device`, `turn_detector_device`: String
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
  /// - `aec_warmup_ms`, `aec_playback_gate_tail_ms`: int
  /// - `stt_language`: String
  ///
  /// Speaker-id gating:
  /// - `speaker_id`: String — speaker-embedding bundle
  /// - `speaker_id_device`: String, `speaker_similarity_threshold`: double
  /// - `enrolled_speaker_embedding`: List<double>? — reference embedding
  ///
  /// [extra_nodes] appends custom Dart nodes to the native graph; their
  /// descriptors are merged into `config['extra_nodes']`.
  ///
  /// With [require_full_stack], start fails (nothing keeps running)
  /// unless the configured stack (audio + VAD, ASR, LLM, TTS) was
  /// built; the error message lists the reasons. A deferred mic
  /// (`auto_listen: false`) does not fail it.
  Future<Map<String, dynamic>> start({
    required Map<String, dynamic> config,
    List<TSAgentNode> extra_nodes = const [],
    bool require_full_stack = false,
    @Deprecated('Use extra_nodes') List<TSAgentNode>? extraNodes,
  }) async {
    _startListeningEvents();
    _startListeningPorts();

    // `extra_nodes` wins; the deprecated `extraNodes` only fills
    // in when it is empty, so an explicitly empty legacy list
    // cannot drop the nodes passed the new way.
    final nodes = extra_nodes.isNotEmpty
        ? extra_nodes
        : (extraNodes ?? const <TSAgentNode>[]);
    final merged = Map<String, dynamic>.from(config);
    if (nodes.isNotEmpty) {
      merged['extra_nodes'] = nodes.map((n) => n.toDescriptor()).toList();
    }

    _nodeDispatcher?.dispose();
    _nodeDispatcher = VoiceAgentNodeDispatcher(
      nodesChannel: _nodesChannel,
      portEvents: port_events,
      sendNodePort: _sendNodePort,
      publishNodeEvent: _publishNodeEvent,
    )..registerNodes(nodes)
      ..installHandler();

    if (require_full_stack) {
      merged['require_full_stack'] = true;
    }
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        MethodRoute.voiceAgentStart,
        merged,
      );
      capabilities = parseAgentCapabilities(result);
    } catch (_) {
      // A failed start leaves nothing running natively; do not
      // keep reporting the previous session's capabilities.
      capabilities = const {};
      rethrow;
    }
    return capabilities;
  }

  /// Open the mic and begin listening after a deferred-mic
  /// `start(config: {'auto_listen': false})` — call once any heavy
  /// deferred local models (e.g. an on-device LLM) are ready.
  /// Idempotent (no-op if already listening).
  Future<void> begin_listening() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      MethodRoute.voiceAgentBeginListening,
    );
    if (result != null) capabilities = parseAgentCapabilities(result);
  }

  /// Stop the voice agent and release all resources.
  Future<void> stop() async {
    await _channel.invokeMethod(MethodRoute.voiceAgentStop);
    _nodeDispatcher?.dispose();
    _nodeDispatcher = null;
    _state = TSAgentState.idle;
    capabilities = const {};
  }

  /// Interrupt the current response (cancel LLM + TTS).
  Future<void> interrupt() async {
    await _channel.invokeMethod(MethodRoute.voiceAgentInterrupt);
  }

  /// Speak text directly, bypassing LLM.
  Future<void> say(String text) async {
    await _channel.invokeMethod(MethodRoute.voiceAgentSay, {'text': text});
  }

  /// Inject a typed user turn, bypassing the mic and ASR. Drives the
  /// same LLM -> TTS path as a spoken turn. No-op if the agent has no
  /// LLM responder (transcription-only).
  Future<void> send_request(String text) async {
    await _channel.invokeMethod(
      MethodRoute.voiceAgentSendRequest,
      {'text': text},
    );
  }

  /// Hot-swap the TTS voice at runtime (reloads the TTS model).
  ///
  /// Pass any subset of [voice_id], [voice_dir] and [language]; `null`
  /// fields keep their current value. [voice_dir] is a voice-pack
  /// folder holding `voice.json` and wins over [voice_id]; an empty
  /// [voice_dir] clears it (back to [voice_id]). An empty [language]
  /// returns to the voice's own language.
  ///
  /// ```dart
  /// await agent.set_voice(voice_id: 'paul');
  /// await agent.set_voice(voice_dir: '/path/to/prepared_pack');
  /// await agent.set_voice(voice_id: 'paul', language: 'french');
  /// await agent.set_voice(voice_dir: '');
  /// ```
  ///
  /// Throws a [PlatformException] when the voice cannot be applied
  /// (relative or missing pack, unknown voice or language, reload
  /// failure); the previous voice stays. If even that cannot be
  /// reloaded, speech is disabled and an `error` event is emitted.
  Future<void> set_voice({
    String? voice_id,
    String? voice_dir,
    String? language,
  }) async {
    final args = <String, dynamic>{};
    if (voice_id != null) args['voice_id'] = voice_id;
    if (voice_dir != null) args['voice_dir'] = voice_dir;
    if (language != null) args['language'] = language;
    if (args.isEmpty) return;
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      MethodRoute.voiceAgentSetVoice,
      args,
    );
    if (result != null) capabilities = parseAgentCapabilities(result);
  }

  /// Clear conversation history.
  Future<void> clear_history() async {
    await _channel.invokeMethod(MethodRoute.voiceAgentClearHistory);
  }

  /// Hot-swap the LLM system prompt for subsequent turns (no agent
  /// restart). History is kept.
  Future<void> set_system_prompt(String prompt) async {
    await _channel.invokeMethod(
      MethodRoute.voiceAgentSetSystemPrompt,
      {'system_prompt': prompt},
    );
  }

  /// Enroll or clear the speaker embedding used by speaker-id gating.
  /// Pass `embedding: null` to clear enrollment. [audio_path]
  /// enrollment is not supported yet; pass [embedding].
  Future<void> enroll_speaker({
    List<double>? embedding,
    String? audio_path,
  }) async {
    if (audio_path != null) {
      throw UnsupportedError(
        'audio_path enrollment is not supported yet; pass embedding instead.',
      );
    }
    await _channel.invokeMethod(MethodRoute.voiceAgentEnrollSpeaker, {
      'embedding': embedding,
    });
  }

  /// Subscribe to a named agent port (`llm.delta`, `vad.probability`, or
  /// a custom node port such as `my_node.caption`).
  Stream<dynamic> subscribe_port(String name) {
    return port_events
        .where((event) => event['port'] == name)
        .map((event) => event['value']);
  }

  /// Hot-update interrupt-related knobs on a running agent. Any `null`
  /// argument is left untouched on the native side.
  ///
  /// - [interrupt_min_speech_ms]: sustained speech (ms) to fire barge-in.
  /// - [interrupt_min_playback_ms]: AEC-converge grace at TTS-turn start.
  /// - [interrupt_mode]: `'none'` | `'speech_only'` | `'wake_word'`.
  /// - [interrupt_onset_ms], [interrupt_threshold]: barge-in onset
  ///   window and VAD probability.
  Future<void> update_interrupt_config({
    int? interrupt_min_speech_ms,
    int? interrupt_min_playback_ms,
    String? interrupt_mode,
    int? interrupt_onset_ms,
    double? interrupt_threshold,
  }) async {
    final args = <String, dynamic>{};
    if (interrupt_min_speech_ms != null) {
      args['interrupt_min_speech_ms'] = interrupt_min_speech_ms;
    }
    if (interrupt_min_playback_ms != null) {
      args['interrupt_min_playback_ms'] = interrupt_min_playback_ms;
    }
    if (interrupt_mode != null) {
      args['interrupt_mode'] = interrupt_mode;
    }
    if (interrupt_onset_ms != null) {
      args['interrupt_onset_ms'] = interrupt_onset_ms;
    }
    if (interrupt_threshold != null) {
      args['interrupt_threshold'] = interrupt_threshold;
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
  // Deprecated camelCase members
  // -------------------------------------------------------------------------

  @Deprecated('Use llm_deltas')
  Stream<String> get llmDeltas => llm_deltas;

  @Deprecated('Use vad_probabilities')
  Stream<double> get vadProbabilities => vad_probabilities;

  @Deprecated('Use port_events')
  Stream<Map<String, dynamic>> get portEvents => port_events;

  @Deprecated('Use begin_listening')
  Future<void> beginListening() => begin_listening();

  @Deprecated('Use send_request')
  Future<void> sendRequest(String text) => send_request(text);

  @Deprecated('Use set_voice(voice_id: ...)')
  Future<void> setVoice(String voice) => set_voice(voice_id: voice);

  @Deprecated('Use clear_history')
  Future<void> clearHistory() => clear_history();

  @Deprecated('Use enroll_speaker')
  Future<void> enrollSpeaker({
    List<double>? embedding,
    String? audioPath,
  }) => enroll_speaker(embedding: embedding, audio_path: audioPath);

  @Deprecated('Use subscribe_port')
  Stream<dynamic> subscribePort(String name) => subscribe_port(name);

  @Deprecated('Use update_interrupt_config')
  Future<void> updateInterruptConfig({
    int? interruptMinSpeechMs,
    int? interruptMinPlaybackMs,
    String? interruptMode,
    int? interruptOnsetMs,
    double? interruptThreshold,
  }) => update_interrupt_config(
    interrupt_min_speech_ms: interruptMinSpeechMs,
    interrupt_min_playback_ms: interruptMinPlaybackMs,
    interrupt_mode: interruptMode,
    interrupt_onset_ms: interruptOnsetMs,
    interrupt_threshold: interruptThreshold,
  );

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
          _state = TSAgentState.fromString(stateStr);
        }

        _controller.add(map);
      },
      onError: (e) => _controller.addError(e),
    );
  }
}

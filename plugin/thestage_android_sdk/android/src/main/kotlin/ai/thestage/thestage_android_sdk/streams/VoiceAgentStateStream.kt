package ai.thestage.thestage_android_sdk.streams

import ai.thestage.qlip.voice_agent.InterruptTrigger
import ai.thestage.qlip.voice_agent.TheStageAgentConfig
import ai.thestage.qlip.voice_agent.TheStageVoiceAgent
import ai.thestage.qlip.voice_agent.graph.InterruptMode
import ai.thestage.qlip.voice_agent.graph.TheStageAgentState
import ai.thestage.qlip.voice_agent.graph.TurnEndMode
import ai.thestage.qlip.voice_agent.graph.TurnStartMode
import ai.thestage.thestage_android_sdk.internal.__parse_devices
import ai.thestage.thestage_android_sdk.internal.__parse_embedding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// ----------------------------------------------------------------------
// VoiceAgentStateStream
// ----------------------------------------------------------------------
/**
 * EventChannel stream handler backing the main
 * `voice_agent_events` channel. Owns the
 * [TheStageVoiceAgent] instance, bridges its `events` flow
 * onto the Dart sink, and binds/unbinds the three
 * broadcast taps ([VoiceAgentBroadcastStream]) over the
 * agent's lifetime. Mirrors Swift's `VoiceAgentStateStream`.
 */
class VoiceAgentStateStream(
    private val __scope: CoroutineScope,
) : EventChannel.StreamHandler {

    // Private Attributes
    // ------------------------------------------------------------------
    private var __event_sink: EventChannel.EventSink? = null
    private var __agent: TheStageVoiceAgent? = null
    private var __event_job: Job? = null
    private val __taps:
        MutableList<VoiceAgentBroadcastStream> =
            mutableListOf()
    private val __bridge_nodes:
        MutableList<FlutterBridgeNode> = mutableListOf()
    private var __nodes_channel: MethodChannel? = null
    private var __port_stream: VoiceAgentPortStream? = null

    // Public Attributes
    // ------------------------------------------------------------------
    val has_sink: Boolean get() = __event_sink != null
    val agent: TheStageVoiceAgent? get() = __agent
    val bridge_nodes: List<FlutterBridgeNode> get() = __bridge_nodes

    // Public Methods
    // ------------------------------------------------------------------
    fun register_tap(tap: VoiceAgentBroadcastStream) {
        __taps.add(tap)
        __agent?.let { tap.bind(it) }
    }

    /** Wire the custom-node method channel + the port multiplexer so
     *  `extra_nodes` and their ports can bridge to Dart. */
    fun configure(
        nodes_channel: MethodChannel,
        port_stream: VoiceAgentPortStream,
    ) {
        __nodes_channel = nodes_channel
        __port_stream = port_stream
    }

    // EventChannel.StreamHandler
    // ------------------------------------------------------------------
    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink?
    ) {
        __event_sink = events
    }

    override fun onCancel(arguments: Any?) {
        __event_job?.cancel()
        __event_job = null
        __event_sink = null
    }

    // Lifecycle
    // ------------------------------------------------------------------
    suspend fun start(config: Map<String, Any?>) {
        // Tear down any agent still running so we never have two live
        // graphs capturing the mic at once - two graphs means two ASR
        // nodes transcribing the same utterance, i.e. doubled replies.
        if (__agent != null) stop()

        val agent_config = __parse_config(config)
        val agent = TheStageVoiceAgent(config = agent_config)
        __agent = agent

        for (tap in __taps) tap.bind(agent)

        val sink = __event_sink
        __event_job = __scope.launch(Dispatchers.Default) {
            agent.events.collect { event ->
                val dict = mutableMapOf<String, Any?>(
                    "kind" to event.kind.raw,
                )
                for ((k, v) in event.data) dict[k] = v
                withContext(Dispatchers.Main) {
                    try {
                        sink?.success(dict)
                    } catch (_: Throwable) {}
                }
            }
        }

        agent.start()
        __port_stream?.bind(agent)
    }

    suspend fun stop() {
        __event_job?.cancel()
        __event_job = null
        for (tap in __taps) tap.unbind()
        __port_stream?.unbind()
        __agent?.stop()
        __agent = null
        __bridge_nodes.clear()
    }

    fun interrupt() {
        __agent?.interrupt()
    }

    suspend fun say(text: String) {
        __agent?.say(text)
    }

    suspend fun set_voice(voice: String) {
        __agent?.set_voice(voice)
    }

    fun clear_history() {
        __agent?.clear_history()
    }

    fun update_interrupt_config(
        min_speech_ms: Int?,
        min_playback_ms: Int?,
        mode: InterruptTrigger?,
        onset_ms: Int?,
        threshold: Double?,
    ) {
        __agent?.update_interrupt_config(
            min_speech_ms = min_speech_ms,
            min_playback_ms = min_playback_ms,
            mode = mode,
            onset_ms = onset_ms,
            threshold = threshold,
        )
    }

    /** Set or clear the enrolled speaker embedding on the live agent. */
    suspend fun enroll_speaker(embedding: DoubleArray?) {
        __agent?.enroll_speaker(embedding)
    }

    /** Open the mic + begin listening after an `auto_listen=false`
     *  start (deferred-mic). No-op if already listening. */
    suspend fun begin_listening() {
        __agent?.begin_listening()
    }

    /** Send a value onto a custom node's named port and register the
     *  reverse forward so the node's emissions reach Dart. */
    fun send_node_port(
        node_id: String,
        port: String,
        value: String,
    ) {
        val node =
            __bridge_nodes.firstOrNull { it.id == node_id } ?: return
        __port_stream?.register_node_port_forward(node, port)
        node.send_port(port, value)
    }

    fun publish_node_event(
        node_id: String,
        event: Map<String, Any?>,
    ) {
        val node =
            __bridge_nodes.firstOrNull { it.id == node_id } ?: return
        node.publish_bus_event(event)
    }

    fun send_request(text: String) {
        __agent?.send_request(text)
    }


    // Private Methods
    // ------------------------------------------------------------------
    private fun __parse_config(
        dict: Map<String, Any?>
    ): TheStageAgentConfig {
        val provider_type =
            dict["llm_provider"] as? String
                ?: "openai_compatible"

        var config = TheStageAgentConfig(
            vad = dict["vad"] as? String
                ?: "TheStageAI/silero-vad",
            stt = dict["stt"] as? String
                ?: "TheStageAI/thewhisper-large-v3-turbo",
            // Absent `tts` -> null (transcription-only). Apps that
            // speak always send it, so this is a no-op for them.
            tts = dict["tts"] as? String,
            wake_word = dict["wake_word"] as? String,
            llm_provider = provider_type,
            // Local engines path (on-device LLM) — distinct from the
            // OpenAI-compatible model name below.
            llm = dict["llm"] as? String,
            llm_model = dict["llm_model"] as? String
                ?: "gpt-4o-mini",
            llm_endpoint = dict["llm_endpoint"] as? String
                ?: "https://api.openai.com/v1/chat/completions",
            llm_api_key = dict["llm_api_key"] as? String ?: "",
        )

        (dict["system_prompt"] as? String)?.let {
            config = config.copy(system_prompt = it)
        }
        __as_int(dict["max_tokens"])?.let {
            config = config.copy(max_tokens = it)
        }
        __as_double(dict["temperature"])?.let {
            config = config.copy(temperature = it)
        }

        (dict["tts_voice"] as? String)?.let {
            config = config.copy(tts_voice = it)
        }
        __as_double(dict["vad_threshold"])?.let {
            config = config.copy(vad_threshold = it)
        }
        __as_int(dict["silence_timeout_ms"])?.let {
            config = config.copy(silence_timeout_ms = it)
        }
        (dict["interrupt_mode"] as? String)?.let {
            config = config.copy(
                interrupt_mode = __parse_interrupt_mode(it)
            )
        }
        // Legacy control: `allow_interruptions` is now a computed
        // property of `interrupt_mode` on the config. Preserve the
        // wire flag by mapping false -> NONE (interruptions off).
        // Applied after the explicit `interrupt_mode` parse so an
        // explicit "off" wins over a mode set in the same call.
        if ((dict["allow_interruptions"] as? Boolean) == false) {
            config = config.copy(interrupt_mode = InterruptMode.NONE)
        }
        __as_double(dict["interrupt_threshold"])?.let {
            config = config.copy(interrupt_threshold = it)
        }
        __as_int(dict["interrupt_min_speech_ms"])?.let {
            config = config.copy(interrupt_min_speech_ms = it)
        }
        __as_int(dict["interrupt_onset_ms"])?.let {
            config = config.copy(interrupt_onset_ms = it)
        }
        __as_int(dict["interrupt_min_playback_ms"])?.let {
            config =
                config.copy(interrupt_min_playback_ms = it)
        }
        __as_int(dict["interrupt_initial_lockout_ms"])?.let {
            config =
                config.copy(interrupt_initial_lockout_ms = it)
        }
        __as_int(dict["interrupt_thinking_lockout_ms"])?.let {
            config =
                config.copy(interrupt_thinking_lockout_ms = it)
        }
        __as_int(dict["pre_roll_ms"])?.let {
            config = config.copy(pre_roll_ms = it)
        }
        (dict["aec_enabled"] as? Boolean)?.let {
            config = config.copy(aec_enabled = it)
        }
        (dict["speculative_whisper"] as? Boolean)?.let {
            config = config.copy(speculative_whisper = it)
        }
        (dict["asr_streaming"] as? Boolean)?.let {
            config = config.copy(asr_streaming = it)
        }
        __as_int(dict["asr_partial_interval_ms"])?.let {
            config = config.copy(asr_partial_interval_ms = it)
        }
        (dict["debug_timeline"] as? Boolean)?.let {
            config = config.copy(debug_timeline = it)
        }
        // `component_offload` is intentionally NOT parsed here — the
        // STT/TTS-LLM memory swap is an internal, not-yet-validated
        // optimization kept on the SDK config for tests only, not an
        // advertised public config surface.
        // Undocumented TTS stream overrides — both default true in
        // the agent config; parsed only so a power user can flip
        // them, not advertised in the public config surface.
        (dict["tts_realtime_gate"] as? Boolean)?.let {
            config = config.copy(tts_realtime_gate = it)
        }
        (dict["tts_chained_chunks"] as? Boolean)?.let {
            config = config.copy(tts_chained_chunks = it)
        }
        // Wire key stays `ww_threshold` (matches iOS's over-the-wire
        // contract); the native field is `ww_threshold_score`.
        __as_double(dict["ww_threshold"])?.let {
            config = config.copy(ww_threshold_score = it)
        }
        __as_int(dict["conversation_timeout_sec"])?.let {
            config = config.copy(conversation_timeout_sec = it)
        }
        (dict["stt_language"] as? String)?.let {
            config = config.copy(stt_language = it)
        }

        (dict["vad_device"] as? String)?.let {
            config = config.copy(vad_device = it)
        }
        (dict["stt_device"] as? String)?.let {
            config = config.copy(stt_device = it)
        }
        (dict["tts_device"] as? String)?.let {
            config = config.copy(tts_device = it)
        }
        (dict["ww_device"] as? String)?.let {
            config = config.copy(ww_device = it)
        }
        __parse_devices(dict["stt_devices"])?.let {
            config = config.copy(stt_devices = it)
        }
        __parse_devices(dict["tts_devices"])?.let {
            config = config.copy(tts_devices = it)
        }

        (dict["stt_revision"] as? String)?.let {
            config = config.copy(stt_revision = it)
        }
        (dict["tts_revision"] as? String)?.let {
            config = config.copy(tts_revision = it)
        }
        (dict["vad_revision"] as? String)?.let {
            config = config.copy(vad_revision = it)
        }
        (dict["ww_revision"] as? String)?.let {
            config = config.copy(ww_revision = it)
        }
        (dict["llm_revision"] as? String)?.let {
            config = config.copy(llm_revision = it)
        }
        (dict["llm_device"] as? String)?.let {
            config = config.copy(llm_device = it)
        }

        // VAD / endpointing extras.
        __as_int(dict["vad_onset_ms"])?.let {
            config = config.copy(vad_onset_ms = it)
        }
        __as_int(dict["max_accumulation_ms"])?.let {
            config = config.copy(max_accumulation_ms = it)
        }

        // Turn detection (endpointing strategy + DNN smart-turn knobs).
        // `turn_start_mode` gates leaving `sleeping`; `turn_end_mode`
        // (legacy alias `turn_detection_mode`) selects the endpointer.
        (dict["turn_start_mode"] as? String)?.let {
            config = config.copy(
                turn_start_mode = TurnStartMode.parse(it)
            )
        }
        (dict["turn_end_mode"] as? String
            ?: dict["turn_detection_mode"] as? String)?.let {
            config = config.copy(turn_end_mode = TurnEndMode.parse(it))
        }
        (dict["turn_detector"] as? String)?.let {
            config = config.copy(turn_detector = it)
        }
        (dict["turn_detector_device"] as? String)?.let {
            config = config.copy(turn_detector_device = it)
        }
        (dict["turn_detector_revision"] as? String)?.let {
            config = config.copy(turn_detector_revision = it)
        }
        __as_double(dict["turn_eot_threshold"])?.let {
            config = config.copy(turn_eot_threshold = it)
        }
        __as_int(dict["turn_eot_confirm_count"])?.let {
            config = config.copy(turn_eot_confirm_count = it)
        }
        __as_double(dict["turn_eot_high_confidence"])?.let {
            config = config.copy(turn_eot_high_confidence = it)
        }
        __as_int(dict["turn_pause_trigger_ms"])?.let {
            config = config.copy(turn_pause_trigger_ms = it)
        }
        __as_int(dict["turn_reeval_interval_ms"])?.let {
            config = config.copy(turn_reeval_interval_ms = it)
        }
        __as_int(dict["turn_max_silence_ms"])?.let {
            config = config.copy(turn_max_silence_ms = it)
        }
        __as_int(dict["turn_window_ms"])?.let {
            config = config.copy(turn_window_ms = it)
        }
        __as_int(dict["turn_min_speech_ms"])?.let {
            config = config.copy(turn_min_speech_ms = it)
        }
        __as_int(dict["turn_asr_silence_hangover_ms"])?.let {
            config = config.copy(turn_asr_silence_hangover_ms = it)
        }

        // Speaker identification (gating + enrollment).
        (dict["speaker_id"] as? String)?.let {
            config = config.copy(speaker_id = it)
        }
        (dict["speaker_id_device"] as? String)?.let {
            config = config.copy(speaker_id_device = it)
        }
        __as_double(dict["speaker_similarity_threshold"])?.let {
            config = config.copy(speaker_similarity_threshold = it)
        }
        __parse_embedding(dict["enrolled_speaker_embedding"])?.let {
            config = config.copy(enrolled_speaker_embedding = it)
        }
        (dict["auto_listen"] as? Boolean)?.let {
            config = config.copy(auto_listen = it)
        }

        // aec_warmup_ms / aec_playback_gate_tail_ms are intentionally
        // NOT parsed from the channel: they stay internal SDK defaults
        // (matching iOS, which keeps them as config fields only).

        // Custom graph nodes bridged to Dart. Each descriptor becomes a
        // FlutterBridgeNode forwarding its lifecycle over the nodes
        // channel. Only wired when the plugin supplied that channel.
        __bridge_nodes.clear()
        val nodes_channel = __nodes_channel
        if (nodes_channel != null) {
            @Suppress("UNCHECKED_CAST")
            val descs =
                dict["extra_nodes"] as? List<Map<String, Any?>>
            if (descs != null) {
                val parsed = mutableListOf<FlutterBridgeNode>()
                for (desc in descs) {
                    val id = desc["id"] as? String ?: continue
                    parsed.add(
                        FlutterBridgeNode(
                            id,
                            __parse_agent_states(desc["run_when"]),
                            nodes_channel,
                        )
                    )
                }
                __bridge_nodes.addAll(parsed)
                config = config.copy(extra_nodes = parsed)
            }
        }

        return config
    }

    private fun __as_int(v: Any?): Int? = when (v) {
        is Int -> v
        is Long -> v.toInt()
        is Number -> v.toInt()
        else -> null
    }

    private fun __as_double(v: Any?): Double? = when (v) {
        is Double -> v
        is Float -> v.toDouble()
        is Int -> v.toDouble()
        is Number -> v.toDouble()
        else -> null
    }

    /**
     * Parse the wire interrupt-mode string into [InterruptMode]. Accepts
     * BOTH the legacy trigger strings (`none` / `speech_only` /
     * `wake_word`) and the five new mode strings, so old and new callers
     * both work. Mirrors iOS's `__parse_interrupt_mode`.
     */
    private fun __parse_interrupt_mode(value: String): InterruptMode =
        when (value) {
            "none" -> InterruptMode.NONE
            "vad", "speech_only" -> InterruptMode.VAD
            "vad_wake_word", "wake_word" ->
                InterruptMode.VAD_WAKE_WORD
            "vad_speaker_id" -> InterruptMode.VAD_SPEAKER_ID
            "vad_speaker_id_wake_word" ->
                InterruptMode.VAD_SPEAKER_ID_WAKE_WORD
            else -> InterruptMode.VAD
        }

    /** Parse a `run_when` string list into agent states (unknown names
     *  dropped). Mirrors iOS's `__parse_agent_states`. */
    private fun __parse_agent_states(
        value: Any?,
    ): Set<TheStageAgentState> {
        val list = value as? List<*> ?: return emptySet()
        return list.mapNotNull { raw ->
            (raw as? String)?.let { s ->
                TheStageAgentState.entries.firstOrNull { it.raw == s }
            }
        }.toSet()
    }
}

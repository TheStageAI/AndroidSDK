package ai.thestage.thestage_android_sdk.internal

// ----------------------------------------------------------------------
// MethodChannels
// ----------------------------------------------------------------------
/**
 * Platform-channel names. Android uses the base
 * `thestage_android_sdk`; the iOS counterpart uses
 * `thestage_apple_sdk`. Suffixes are identical across
 * platforms so the shared Dart layer routes by suffix.
 */
internal object MethodChannels {
    const val MAIN = "thestage_android_sdk"
    const val PROGRESS = "thestage_android_sdk/progress"
    const val TTS_STREAM = "thestage_android_sdk/tts_stream"
    const val VOICE_AGENT_EVENTS =
        "thestage_android_sdk/voice_agent_events"
    const val VOICE_AGENT_LLM_DELTAS =
        "thestage_android_sdk/voice_agent_llm_deltas"
    const val VOICE_AGENT_TRANSCRIPTS =
        "thestage_android_sdk/voice_agent_transcripts"
    const val VOICE_AGENT_VAD_PROBABILITIES =
        "thestage_android_sdk/voice_agent_vad_probabilities"
    const val VOICE_AGENT_PORTS =
        "thestage_android_sdk/voice_agent_ports"
    const val VOICE_AGENT_NODES =
        "thestage_android_sdk/voice_agent_nodes"
    const val LOGS = "thestage_android_sdk/logs"
}

// ----------------------------------------------------------------------
// MethodRoute
// ----------------------------------------------------------------------
/**
 * Method-route names. These are IDENTICAL to the iOS
 * `MethodRoute` constants and the shared Dart
 * `MethodRoute` so a single Dart call site reaches
 * either platform unchanged.
 *
 * The `ANDROID_*` block at the bottom are Android-only
 * routes with no iOS equivalent (prefetch, NeuTTS-chained
 * toggle, model-availability check). They are preserved
 * from the original `thestage_android_sdk` plugin so Android apps keep
 * working.
 */
internal object MethodRoute {
    const val INITIALIZE = "initialize"
    const val START_MODEL = "start_model"
    const val STOP_MODEL = "stop_model"

    const val LIST_COMPONENTS = "list_components"
    const val LOAD_COMPONENTS = "load_components"
    const val UNLOAD_COMPONENTS = "unload_components"
    const val BUNDLED_ENGINE_PATH = "get_bundled_engine_path"

    const val MEMORY_FOOTPRINT = "memory_footprint"

    const val INFER = "infer"
    const val START_STREAM = "start_stream"
    const val SEND = "send"
    const val FINISH_STREAM = "finish_stream"
    const val STOP_STREAM = "stop_stream"

    const val AUDIO_START = "audio_start"
    const val AUDIO_ENQUEUE = "audio_enqueue"
    const val AUDIO_PAUSE = "audio_pause"
    const val AUDIO_RESUME = "audio_resume"
    const val AUDIO_DRAIN = "audio_drain"
    const val AUDIO_STOP = "audio_stop"

    const val VOICE_AGENT_START = "voice_agent.start"
    const val VOICE_AGENT_STOP = "voice_agent.stop"
    const val VOICE_AGENT_INTERRUPT = "voice_agent.interrupt"
    const val VOICE_AGENT_SAY = "voice_agent.say"
    const val VOICE_AGENT_SET_VOICE = "voice_agent.set_voice"
    const val VOICE_AGENT_CLEAR_HISTORY =
        "voice_agent.clear_history"
    const val VOICE_AGENT_UPDATE_INTERRUPT_CONFIG =
        "voice_agent.update_interrupt_config"
    const val VOICE_AGENT_ENROLL_SPEAKER =
        "voice_agent.enroll_speaker"
    const val VOICE_AGENT_BEGIN_LISTENING =
        "voice_agent.begin_listening"
    const val VOICE_AGENT_SEND_NODE_PORT =
        "voice_agent.send_node_port"
    const val VOICE_AGENT_PUBLISH_NODE_EVENT =
        "voice_agent.publish_node_event"
    const val VOICE_AGENT_SEND_REQUEST =
        "voice_agent.send_request"

    const val SCREEN_RECORDER_IS_RECORDING =
        "screen_recorder.is_recording"
    const val SCREEN_RECORDER_START = "screen_recorder.start"
    const val SCREEN_RECORDER_STOP = "screen_recorder.stop"

    // Android-only routes (no iOS equivalent). Preserved
    // from the original thestage_android_sdk plugin, snake_cased.
    const val ANDROID_PREFETCH_MODEL = "prefetch_model"
    const val ANDROID_CHECK_MODEL_AVAILABILITY =
        "check_model_availability"
}

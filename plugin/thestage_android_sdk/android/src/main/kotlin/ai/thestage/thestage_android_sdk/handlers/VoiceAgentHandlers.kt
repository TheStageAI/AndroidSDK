package ai.thestage.thestage_android_sdk.handlers

import ai.thestage.qlip.voice_agent.InterruptTrigger
import ai.thestage.thestage_android_sdk.TheStageFlutterPlugin
import ai.thestage.thestage_android_sdk.internal.__fail
import ai.thestage.thestage_android_sdk.internal.__parse_embedding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// ----------------------------------------------------------------------
// Voice Agent Handlers
// ----------------------------------------------------------------------
//
// The handlers delegate to the [VoiceAgentStateStream] that
// owns the [TheStageVoiceAgent]; the 4 voice-agent
// EventChannels are wired in [TheStageFlutterPlugin].

@Suppress("UNCHECKED_CAST")
internal fun TheStageFlutterPlugin.__handle_voice_agent_start(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val handler = __voice_agent_handler
    if (handler == null) {
        __fail(result, "Voice agent handler not initialized.")
        return
    }
    val config =
        (call.arguments as? Map<String, Any?>) ?: emptyMap()
    // start() loads VAD / wake-word / Whisper / TTS / LLM inline —
    // mmap + Genie/QNN context creation must not run on the main
    // thread (ANR otherwise), matching __handle_start_model.
    __scope.launch(Dispatchers.Default) {
        try {
            handler.start(config = config)
            withContext(Dispatchers.Main) { result.success(null) }
        } catch (e: Exception) {
            withContext(Dispatchers.Main) { __fail(result, e) }
        }
    }
}

internal fun TheStageFlutterPlugin.__handle_voice_agent_stop(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val handler = __voice_agent_handler
    if (handler == null) {
        result.success(null)
        return
    }
    __scope.launch(Dispatchers.Default) {
        try { handler.stop() } catch (_: Throwable) {}
        withContext(Dispatchers.Main) { result.success(null) }
    }
}

internal fun TheStageFlutterPlugin.__handle_voice_agent_interrupt(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    __voice_agent_handler?.interrupt()
    result.success(null)
}

internal fun TheStageFlutterPlugin.__handle_voice_agent_say(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val args = call.arguments as? Map<*, *>
    val text = args?.get("text") as? String
    if (text == null) {
        __fail(result, "Missing text.")
        return
    }
    __scope.launch(Dispatchers.Default) {
        try { __voice_agent_handler?.say(text) } catch (_: Throwable) {}
        withContext(Dispatchers.Main) { result.success(null) }
    }
}

internal fun TheStageFlutterPlugin.__handle_voice_agent_set_voice(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val args = call.arguments as? Map<*, *>
    val voice = args?.get("voice") as? String
    if (voice == null) {
        __fail(result, "Missing voice.")
        return
    }
    __scope.launch(Dispatchers.Default) {
        try {
            __voice_agent_handler?.set_voice(voice)
        } catch (_: Throwable) {}
        withContext(Dispatchers.Main) { result.success(null) }
    }
}

internal fun TheStageFlutterPlugin.__handle_voice_agent_clear_history(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    __voice_agent_handler?.clear_history()
    result.success(null)
}

internal fun
    TheStageFlutterPlugin.__handle_voice_agent_update_interrupt_config(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val args = (call.arguments as? Map<*, *>) ?: emptyMap<Any?, Any?>()
    val min_speech_ms =
        (args["interrupt_min_speech_ms"] as? Number)?.toInt()
    val min_playback_ms =
        (args["interrupt_min_playback_ms"] as? Number)?.toInt()
    val onset_ms =
        (args["interrupt_onset_ms"] as? Number)?.toInt()
    val threshold =
        (args["interrupt_threshold"] as? Number)?.toDouble()
    val mode = when (args["interrupt_mode"] as? String) {
        "none" -> InterruptTrigger.NONE
        "wake_word" -> InterruptTrigger.WAKE_WORD
        "speech_only" -> InterruptTrigger.SPEECH_ONLY
        else -> null
    }
    __voice_agent_handler?.update_interrupt_config(
        min_speech_ms = min_speech_ms,
        min_playback_ms = min_playback_ms,
        mode = mode,
        onset_ms = onset_ms,
        threshold = threshold,
    )
    result.success(null)
}

internal fun TheStageFlutterPlugin.__handle_voice_agent_enroll_speaker(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val handler = __voice_agent_handler
    if (handler == null) {
        __fail(result, "Voice agent handler not initialized.")
        return
    }
    val args = (call.arguments as? Map<*, *>) ?: emptyMap<Any?, Any?>()
    val embedding = __parse_embedding(args["embedding"])
    __scope.launch(Dispatchers.Default) {
        try { handler.enroll_speaker(embedding) } catch (_: Throwable) {}
        withContext(Dispatchers.Main) { result.success(null) }
    }
}

internal fun TheStageFlutterPlugin.__handle_voice_agent_begin_listening(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val handler = __voice_agent_handler
    if (handler == null) {
        __fail(result, "Voice agent handler not initialized.")
        return
    }
    __scope.launch(Dispatchers.Default) {
        try { handler.begin_listening() } catch (_: Throwable) {}
        withContext(Dispatchers.Main) { result.success(null) }
    }
}

internal fun TheStageFlutterPlugin.__handle_voice_agent_send_node_port(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val handler = __voice_agent_handler
    if (handler == null) {
        __fail(result, "Voice agent handler not initialized.")
        return
    }
    val args = call.arguments as? Map<*, *>
    val node_id = args?.get("node_id") as? String
    val port = args?.get("port") as? String
    val value = args?.get("value") as? String
    if (node_id == null || port == null || value == null) {
        __fail(result, "Missing node_id, port, or value.")
        return
    }
    handler.send_node_port(node_id, port, value)
    result.success(null)
}

internal fun TheStageFlutterPlugin.__handle_voice_agent_publish_node_event(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val handler = __voice_agent_handler
    if (handler == null) {
        __fail(result, "Voice agent handler not initialized.")
        return
    }
    val args = call.arguments as? Map<*, *>
    val node_id = args?.get("node_id") as? String
    @Suppress("UNCHECKED_CAST")
    val event = args?.get("event") as? Map<String, Any?>
    if (node_id == null || event == null) {
        __fail(result, "Missing node_id or event.")
        return
    }
    handler.publish_node_event(node_id, event)
    result.success(null)
}

internal fun TheStageFlutterPlugin.__handle_voice_agent_send_request(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val handler = __voice_agent_handler
    if (handler == null) {
        __fail(result, "Voice agent handler not initialized.")
        return
    }
    val args = call.arguments as? Map<*, *>
    val text = args?.get("text") as? String
    if (text == null) {
        __fail(result, "Missing text.")
        return
    }
    handler.send_request(text)
    result.success(null)
}


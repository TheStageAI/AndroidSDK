package ai.thestage.thestage_android_sdk.handlers

import ai.thestage.qlip.TheStageAI
import ai.thestage.qlip.TypesConverter
import ai.thestage.qlip.models.asr.ASREngine
import ai.thestage.qlip.models.asr.ASRGenerationConfig
import ai.thestage.qlip.models.asr.ASRModelAPI
import ai.thestage.thestage_android_sdk.TheStageFlutterPlugin
import ai.thestage.thestage_android_sdk.internal.ASRJson
import ai.thestage.thestage_android_sdk.internal.__fail
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// ----------------------------------------------------------------------
// Inference Handlers
// ----------------------------------------------------------------------

@Suppress("UNCHECKED_CAST")
internal fun TheStageFlutterPlugin.__handle_infer(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val args = call.arguments as? Map<String, Any>
    if (args == null) {
        __fail(result, "Missing arguments.")
        return
    }
    val model_name = args["model_name"] as? String
    if (model_name == null) {
        __fail(result, "Missing model_name.")
        return
    }
    val input_json = (args["input_json"] as? Map<String, Any?>)
        ?: args.mapValues { it.value }

    // `vad_model_name` with audio: the clip goes through
    // ASREngine(stt, vad), whose VAD moves window cuts into pauses
    // and skips windows without speech.
    val vad_name = (input_json["vad_model_name"] as? String)
        ?.takeIf { it.isNotEmpty() }
    val audio = input_json["audio"] ?: input_json["pcm"]

    __scope.launch(Dispatchers.Default) {
        try {
            if (vad_name != null && audio != null) {
                val pcm = ASRModelAPI.pcm(audio)
                val generation = ASRGenerationConfig.from_payload(
                    payload = input_json,
                    default_language = "en",
                )
                val asr = ASREngine(stt = model_name, vad = vad_name)
                    .infer(pcm, generation)
                val packed = listOf(ASRJson.result(asr))
                withContext(Dispatchers.Main) {
                    result.success(packed)
                }
                return@launch
            }
            val response = TheStageAI.infer(
                model_name = model_name,
                input_json = input_json,
            )
            val packed = TypesConverter.pack_json(response)
            withContext(Dispatchers.Main) {
                result.success(packed)
            }
        } catch (e: Exception) {
            withContext(Dispatchers.Main) {
                __fail(result, e)
            }
        }
    }
}

@Suppress("UNCHECKED_CAST")
internal fun TheStageFlutterPlugin.__handle_start_stream(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val args = call.arguments as? Map<String, Any?>
    val model_name = args?.get("model_name") as? String
    val stream_id = args?.get("stream_id") as? String
    if (model_name == null || stream_id == null) {
        __fail(result, "Missing model_name or stream_id.")
        return
    }
    val handler = __stream_handler
    if (handler == null) {
        __fail(result, "Stream channel not ready.")
        return
    }

    val input_json =
        (args["input_json"] as? Map<String, Any?>) ?: emptyMap()

    val sink_status =
        if (handler.has_sink) "sink_SET" else "sink_NIL"
    // `kind: 'asr'` (Dart `ASRStream.open`): a push ASR session
    // fed by `send {pcm}`; everything else is the generic path.
    if ((args["kind"] as? String)?.lowercase() == "asr") {
        __asr_handler?.start(
            stream_id = stream_id,
            model_name = model_name,
            input_json = input_json,
        )
    } else {
        handler.start(
            stream_id = stream_id,
            model_name = model_name,
            input_json = input_json,
        )
    }
    result.success(mapOf("sink_status" to sink_status))
}

internal fun TheStageFlutterPlugin.__handle_send_stream(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val args = call.arguments as? Map<*, *>
    val stream_id = args?.get("stream_id") as? String
    if (stream_id == null) {
        __fail(result, "Missing stream_id.")
        return
    }
    val pcm = args["pcm"]
    val text = args["text"] as? String
    when {
        pcm != null -> {
            val samples = try {
                ASRModelAPI.pcm(pcm)
            } catch (e: Exception) {
                __fail(result, "Unsupported pcm payload.")
                return
            }
            __asr_handler?.send(stream_id = stream_id, pcm = samples)
        }
        text != null ->
            __stream_handler?.send(stream_id = stream_id, text = text)
        else -> {
            __fail(result, "Missing stream_id payload (text or pcm).")
            return
        }
    }
    result.success(null)
}

internal fun TheStageFlutterPlugin.__handle_flush_stream(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val args = call.arguments as? Map<*, *>
    val stream_id = args?.get("stream_id") as? String
    if (stream_id == null) {
        __fail(result, "Missing stream_id.")
        return
    }
    __asr_handler?.flush(stream_id = stream_id)
    result.success(null)
}

internal fun TheStageFlutterPlugin.__handle_finish_stream(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val args = call.arguments as? Map<*, *>
    val stream_id = args?.get("stream_id") as? String
    if (stream_id == null) {
        __fail(result, "Missing stream_id.")
        return
    }
    val asr = __asr_handler
    if (asr != null && asr.has(stream_id)) {
        // Replies with the session's final ASRResult.
        __scope.launch(Dispatchers.Default) {
            val payload = try {
                ASRJson.result(asr.close(stream_id))
            } catch (e: Exception) {
                withContext(Dispatchers.Main) { __fail(result, e) }
                return@launch
            }
            withContext(Dispatchers.Main) { result.success(payload) }
        }
        return
    }
    __stream_handler?.finish_stream(stream_id = stream_id)
    result.success(null)
}

internal fun TheStageFlutterPlugin.__handle_stop_stream(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val args = call.arguments as? Map<*, *>
    val stream_id = args?.get("stream_id") as? String
    if (stream_id == null) {
        __fail(result, "Missing stream_id.")
        return
    }
    val asr = __asr_handler
    if (asr != null && asr.has(stream_id)) {
        asr.cancel(stream_id = stream_id)
    } else {
        __stream_handler?.cancel(stream_id = stream_id)
    }
    result.success(null)
}

// ----------------------------------------------------------------------
// Streaming input (push INTO a live infer_stream session)
// ----------------------------------------------------------------------
/**
 * Shared body for the three streaming-input routes. Each takes
 * `{model_name, input_json?}` and forwards to the matching
 * [TheStageAI] call on the model's own executor.
 *
 * Only models whose streaming path accepts input after the
 * stream opens support these — Nemotron diarization and
 * `nemotron-multispeaker`; everything else answers with an
 * error the Dart side surfaces as-is.
 */
@Suppress("UNCHECKED_CAST")
private fun TheStageFlutterPlugin.__handle_stream_input(
    call: MethodCall,
    result: MethodChannel.Result,
    body: suspend (String, Map<String, Any?>) -> Unit,
) {
    val args = call.arguments as? Map<String, Any?>
    val model_name = args?.get("model_name") as? String
    if (model_name == null) {
        __fail(result, "Missing model_name.")
        return
    }
    val input_json =
        (args["input_json"] as? Map<String, Any?>) ?: emptyMap()

    __scope.launch(Dispatchers.Default) {
        try {
            body(model_name, input_json)
            withContext(Dispatchers.Main) { result.success(null) }
        } catch (e: Exception) {
            withContext(Dispatchers.Main) { __fail(result, e) }
        }
    }
}

internal fun TheStageFlutterPlugin.__handle_stream_append(
    call: MethodCall,
    result: MethodChannel.Result,
) = __handle_stream_input(call, result) { model_name, input_json ->
    TheStageAI.stream_append(model_name, input_json)
}

internal fun TheStageFlutterPlugin.__handle_stream_finish(
    call: MethodCall,
    result: MethodChannel.Result,
) = __handle_stream_input(call, result) { model_name, input_json ->
    TheStageAI.stream_finish(model_name, input_json)
}

internal fun TheStageFlutterPlugin.__handle_stream_cancel(
    call: MethodCall,
    result: MethodChannel.Result,
) = __handle_stream_input(call, result) { model_name, input_json ->
    TheStageAI.stream_cancel(model_name, input_json)
}

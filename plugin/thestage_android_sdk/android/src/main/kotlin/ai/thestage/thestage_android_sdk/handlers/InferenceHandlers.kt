package ai.thestage.thestage_android_sdk.handlers

import ai.thestage.qlip.TheStageAI
import ai.thestage.qlip.TypesConverter
import ai.thestage.thestage_android_sdk.TheStageFlutterPlugin
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

    __scope.launch(Dispatchers.Default) {
        try {
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
    handler.start(
        stream_id = stream_id,
        model_name = model_name,
        input_json = input_json,
    )
    result.success(mapOf("sink_status" to sink_status))
}

internal fun TheStageFlutterPlugin.__handle_send_stream(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val args = call.arguments as? Map<*, *>
    val stream_id = args?.get("stream_id") as? String
    val text = args?.get("text") as? String
    if (stream_id == null || text == null) {
        __fail(result, "Missing stream_id or text.")
        return
    }
    __stream_handler?.send(stream_id = stream_id, text = text)
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
    __stream_handler?.cancel(stream_id = stream_id)
    result.success(null)
}

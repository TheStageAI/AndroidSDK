package ai.thestage.thestage_android_sdk.handlers

import ai.thestage.qlip.TheStageAI
import ai.thestage.thestage_android_sdk.TheStageFlutterPlugin
import ai.thestage.thestage_android_sdk.internal.__fail
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// ----------------------------------------------------------------------
// Component Handlers
// ----------------------------------------------------------------------

internal fun TheStageFlutterPlugin.__handle_list_components(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val args = call.arguments as? Map<*, *>
    val model_name = args?.get("model_name") as? String
    if (model_name == null) {
        __fail(result, "Missing model_name.")
        return
    }
    __scope.launch(Dispatchers.Default) {
        try {
            val statuses = TheStageAI.list_components(
                model_name = model_name
            )
            withContext(Dispatchers.Main) {
                result.success(statuses)
            }
        } catch (e: Exception) {
            withContext(Dispatchers.Main) {
                __fail(result, e)
            }
        }
    }
}

internal fun TheStageFlutterPlugin.__handle_load_components(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    __handle_component_mutation(call, result) { name, ids ->
        TheStageAI.load_components(
            model_name = name, component_ids = ids
        )
    }
}

internal fun TheStageFlutterPlugin.__handle_unload_components(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    __handle_component_mutation(call, result) { name, ids ->
        TheStageAI.unload_components(
            model_name = name, component_ids = ids
        )
    }
}

@Suppress("UNCHECKED_CAST")
private fun TheStageFlutterPlugin.__handle_component_mutation(
    call: MethodCall,
    result: MethodChannel.Result,
    action: suspend (
        String, List<String>
    ) -> List<Map<String, Any>>,
) {
    val args = call.arguments as? Map<String, Any?>
    val name = args?.get("model_name") as? String
    val ids = (args?.get("component_ids") as? List<Any?>)
        ?.mapNotNull { it as? String }
    if (name == null || ids == null) {
        __fail(
            result,
            "Missing model_name or component_ids."
        )
        return
    }
    __scope.launch(Dispatchers.Default) {
        try {
            val r = action(name, ids)
            withContext(Dispatchers.Main) {
                result.success(r)
            }
        } catch (e: Exception) {
            withContext(Dispatchers.Main) {
                __fail(result, e)
            }
        }
    }
}

internal fun TheStageFlutterPlugin.__handle_bundled_engine_path(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val args = call.arguments as? Map<*, *>
    val filename = args?.get("filename") as? String
    if (filename == null) {
        __fail(result, "Missing filename.")
        return
    }
    // Android doesn't have a direct bundle path like iOS.
    // Assets must be extracted first.
    result.success(null)
}

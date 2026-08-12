package ai.thestage.thestage_android_sdk.handlers

import ai.thestage.qlip.TheStageAI
import ai.thestage.thestage_android_sdk.TheStageFlutterPlugin
import ai.thestage.thestage_android_sdk.internal.__fail
import ai.thestage.thestage_android_sdk.internal.__load_progress_event
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// ----------------------------------------------------------------------
// Android-only Handlers
// ----------------------------------------------------------------------
//
// Routes with no iOS equivalent, preserved (snake_cased)
// from the original thestage_android_sdk plugin: prefetch_model,
// check_model_availability.

@Suppress("UNCHECKED_CAST")
internal fun TheStageFlutterPlugin.__handle_prefetch_model(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val args = call.arguments as? Map<String, Any>
    if (args == null) {
        __fail(result, "Missing arguments.")
        return
    }
    val repo_id = args["repo_id"] as? String
    if (repo_id == null) {
        __fail(result, "Missing repo_id.")
        return
    }
    val model_type = args["model_type"] as? String
    val revision = args["revision"] as? String ?: "main"
    val config = args["config"] as? Map<String, Any?>

    // Progress events for prefetch_model use `repo_id` as
    // the model_name field — same convention as iOS so the
    // Dart dispatch can match either prefetch or start_model
    // events with a single lookup.
    val on_load_progress:
        ai.thestage.qlip.utils.LoadProgressHandler? =
        __progress_sink?.let { sink ->
            { event ->
                __scope.launch {
                    sink.success(
                        __load_progress_event(repo_id, event)
                    )
                }
            }
        }

    __scope.launch(Dispatchers.Default) {
        try {
            val path = TheStageAI.prefetch_model(
                repo_id = repo_id,
                model_type = model_type,
                revision = revision,
                config = config,
                on_load_progress = on_load_progress,
            )
            withContext(Dispatchers.Main) {
                result.success(path)
            }
        } catch (e: Exception) {
            withContext(Dispatchers.Main) {
                __fail(result, e)
            }
        }
    }
}

/**
 * HEAD-only availability probe for an engines bundle —
 * resolvable before initialize, no token, no download.
 * Runs off the main thread.
 */
@Suppress("UNCHECKED_CAST")
internal fun TheStageFlutterPlugin.__handle_check_model_availability(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val args = call.arguments as? Map<String, Any?>
    val model_path = args?.get("model_path") as? String
    if (model_path == null) {
        __fail(result, "Missing model_path.")
        return
    }
    val revision = args["revision"] as? String ?: "main"

    __scope.launch(Dispatchers.Default) {
        try {
            val r = TheStageAI.check_model_availability(
                model_path = model_path,
                revision = revision,
            )
            withContext(Dispatchers.Main) {
                result.success(
                    mapOf(
                        "availability" to r.availability.raw_value,
                        "reason" to r.reason?.raw_value,
                        "variant" to r.variant,
                        "compute" to r.compute?.raw_value,
                        "source" to r.source,
                        "bundle_size_bytes" to r.bundle_size_bytes,
                    )
                )
            }
        } catch (e: Exception) {
            withContext(Dispatchers.Main) {
                __fail(result, e)
            }
        }
    }
}

package ai.thestage.thestage_android_sdk.handlers

import ai.thestage.qlip.TheStageAI
import ai.thestage.qlip.delivery.InstalledModel
import ai.thestage.qlip.delivery.ModelUpdate
import ai.thestage.qlip.delivery.SlotIntegrity
import ai.thestage.qlip.delivery.SweepResult
import ai.thestage.thestage_android_sdk.TheStageFlutterPlugin
import ai.thestage.thestage_android_sdk.internal.__fail
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// ----------------------------------------------------------------------
// DeliveryHandlers
// ----------------------------------------------------------------------
// The model-lifecycle routes: what is installed, what could be
// replaced, and removing a bundle.
//
// Every key written here is read by name on the Dart side and
// nothing type-checks across the boundary, so the two halves are a
// string contract. ChannelKeyParityTest reads both files and fails
// when they drift — a mistyped key would otherwise decode to a
// silent default rather than an error.

/** `installed_models()` -> List<Map>. */
internal fun TheStageFlutterPlugin.__handle_installed_models(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    __scope.launch(Dispatchers.Default) {
        try {
            val out = TheStageAI.installed_models()
                .map { __encode_installed(it) }
            withContext(Dispatchers.Main) { result.success(out) }
        } catch (e: Exception) {
            withContext(Dispatchers.Main) { __fail(result, e) }
        }
    }
}

/** `available_updates()` -> List<Map>. Reports only. */
internal fun TheStageFlutterPlugin.__handle_available_updates(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    __scope.launch(Dispatchers.Default) {
        try {
            val out = TheStageAI.available_updates()
                .map { __encode_update(it) }
            withContext(Dispatchers.Main) { result.success(out) }
        } catch (e: Exception) {
            withContext(Dispatchers.Main) { __fail(result, e) }
        }
    }
}

/** `update_available(model_type, variant?, repository?)` ->
 *  Map or null. */
internal fun TheStageFlutterPlugin.__handle_update_available(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    @Suppress("UNCHECKED_CAST")
    val args = call.arguments as? Map<String, Any?>
    val model_type = args?.get("model_type") as? String
    if (model_type == null) {
        __fail(result, "Missing model_type.")
        return
    }
    // Absent / empty variant means "this device" — the SDK
    // detects it.
    val variant = (args["variant"] as? String)
        ?.takeIf { it.isNotEmpty() }
    val repository = (args["repository"] as? String)
        ?.takeIf { it.isNotEmpty() }

    __scope.launch(Dispatchers.Default) {
        try {
            val u = TheStageAI.update_available(
                model_type = model_type,
                variant = variant,
                repository = repository,
            )
            withContext(Dispatchers.Main) {
                result.success(u?.let { __encode_update(it) })
            }
        } catch (e: Exception) {
            withContext(Dispatchers.Main) { __fail(result, e) }
        }
    }
}

/** `remove_model(model_type, variant?, repository?)` -> bytes freed. */
internal fun TheStageFlutterPlugin.__handle_remove_model(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    @Suppress("UNCHECKED_CAST")
    val args = call.arguments as? Map<String, Any?>
    val model_type = args?.get("model_type") as? String
    if (model_type == null) {
        __fail(result, "Missing model_type.")
        return
    }
    val variant = (args["variant"] as? String)
        ?.takeIf { it.isNotEmpty() }
    val repository = (args["repository"] as? String)
        ?.takeIf { it.isNotEmpty() }

    __scope.launch(Dispatchers.Default) {
        try {
            val freed = TheStageAI.remove_model(
                model_type = model_type,
                variant = variant,
                repository = repository,
            )
            withContext(Dispatchers.Main) { result.success(freed) }
        } catch (e: Exception) {
            withContext(Dispatchers.Main) { __fail(result, e) }
        }
    }
}

/** `verify_model(model_type, variant?, repository?)` -> Map.
 *  Reports only. */
internal fun TheStageFlutterPlugin.__handle_verify_model(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    @Suppress("UNCHECKED_CAST")
    val args = call.arguments as? Map<String, Any?>
    val model_type = args?.get("model_type") as? String
    if (model_type == null) {
        __fail(result, "Missing model_type.")
        return
    }
    val variant = (args["variant"] as? String)
        ?.takeIf { it.isNotEmpty() }

    val repository = (args["repository"] as? String)
        ?.takeIf { it.isNotEmpty() }

    __scope.launch(Dispatchers.Default) {
        try {
            val r = TheStageAI.verify_model(
                model_type, variant, repository,
            )
            withContext(Dispatchers.Main) {
                result.success(__encode_integrity(r))
            }
        } catch (e: Exception) {
            withContext(Dispatchers.Main) { __fail(result, e) }
        }
    }
}

/** `repair_model(model_type, variant?, repository?)` -> bool.
 *  May download. */
internal fun TheStageFlutterPlugin.__handle_repair_model(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    @Suppress("UNCHECKED_CAST")
    val args = call.arguments as? Map<String, Any?>
    val model_type = args?.get("model_type") as? String
    if (model_type == null) {
        __fail(result, "Missing model_type.")
        return
    }
    val variant = (args["variant"] as? String)
        ?.takeIf { it.isNotEmpty() }

    val repository = (args["repository"] as? String)
        ?.takeIf { it.isNotEmpty() }

    __scope.launch(Dispatchers.Default) {
        try {
            val ok = TheStageAI.repair_model(
                model_type, variant, repository,
            )
            withContext(Dispatchers.Main) { result.success(ok) }
        } catch (e: Exception) {
            withContext(Dispatchers.Main) { __fail(result, e) }
        }
    }
}

// ----------------------------------------------------------------------
// Encoders
// ----------------------------------------------------------------------

private fun __encode_installed(
    m: InstalledModel,
): Map<String, Any?> {
    return mapOf(
        "model_type" to m.model_type,
        "variant" to m.variant,
        "source" to m.source.raw_value,
        "identity" to m.identity,
        "repository" to m.repository,
        "source_repo" to m.source_repo,
        "slot" to m.slot,
        "bytes" to m.bytes,
        "archive" to m.archive,
        "archive_bytes" to m.archive_bytes,
        "retained_reason" to m.retained_reason,
        "content_sha256" to m.content_sha256,
        // Signed build time, both routes. The one version a pack
        // can be ordered against.
        "built_at" to m.built_at,
        // What the app last asked for; diverges from `identity`
        // when a new pack tag is declared and the staged bundle
        // keeps being served.
        "declared_identity" to m.declared_identity,
        // The route the app last named. Differs from `source`
        // exactly when a route change is pending.
        "declared_source" to m.declared_source?.raw_value,
        // Null = genuinely unknown, which is the honest answer for
        // a pack whose bytes match nothing currently pinned.
        "hf_revision" to m.hf_revision,
        // True = Play also holds this pack's copy, so removing the
        // model frees `bytes` and no more.
        "play_copy_retained" to m.play_copy_retained,
        "installed_at" to m.installed_at,
        // Computed on the Kotlin side; carried so the two sides
        // cannot disagree about what a model occupies.
        "total_bytes" to m.total_bytes,
    )
}

private fun __encode_update(
    u: ModelUpdate,
): Map<String, Any?> {
    return mapOf(
        "model_type" to u.model_type,
        "variant" to u.variant,
        // Null for a pack or a local tree.
        "repository" to u.repository,
        "installed" to u.installed,
        "available" to u.available,
        // Which comparison this is: `installed`/`available` are
        // commits or release tags depending on it, and are never
        // comparable across kinds.
        "kind" to u.kind.raw_value,
    )
}

private fun __encode_integrity(
    s: SlotIntegrity,
): Map<String, Any?> {
    return mapOf(
        "verified" to s.verified,
        // False means the bundle carries no integrity data, so
        // there was nothing to check against -- not corruption.
        "verifiable" to s.verifiable,
        "reason" to s.reason,
    )
}

/** `maintain_models()` -> {freed_bytes, removed_paths}. */
internal fun TheStageFlutterPlugin.__handle_maintain_models(
    result: MethodChannel.Result,
) {
    __scope.launch(Dispatchers.Default) {
        try {
            val r = TheStageAI.maintain()
            withContext(Dispatchers.Main) {
                result.success(__encode_sweep(r))
            }
        } catch (e: Exception) {
            withContext(Dispatchers.Main) { __fail(result, e) }
        }
    }
}

/** `reset_models()` -> bytes freed. Refuses while a model is
 *  loaded. */
internal fun TheStageFlutterPlugin.__handle_reset_models(
    result: MethodChannel.Result,
) {
    __scope.launch(Dispatchers.Default) {
        try {
            val freed = TheStageAI.reset_models()
            withContext(Dispatchers.Main) { result.success(freed) }
        } catch (e: Exception) {
            withContext(Dispatchers.Main) { __fail(result, e) }
        }
    }
}

internal fun __encode_sweep(r: SweepResult): Map<String, Any> {
    return mapOf(
        "freed_bytes" to r.freed_bytes,
        "removed_paths" to r.removed_paths,
    )
}

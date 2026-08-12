package ai.thestage.thestage_android_sdk.internal

import ai.thestage.qlip.InferenceStreamChunk
import ai.thestage.qlip.ModelManagerError
import ai.thestage.qlip.ModelStatus
import ai.thestage.qlip.TheStageAI
import io.flutter.plugin.common.MethodChannel

// ----------------------------------------------------------------------
// PluginHelpers
// ----------------------------------------------------------------------
/**
 * Shared argument-parsing, encoding, and error-mapping
 * helpers for the handler extensions. Mirrors Swift's
 * `internal/PluginHelpers.swift`.
 */

// Argument parsing
// ----------------------------------------------------------------------
@Suppress("UNCHECKED_CAST")
internal fun __parse_devices(
    value: Any?
): Map<String, String>? {
    val raw = value as? Map<String, Any> ?: return null
    val parsed = mutableMapOf<String, String>()
    for ((key, v) in raw) {
        if (v is String) parsed[key] = v
    }
    return if (parsed.isEmpty()) null else parsed
}

// Speaker embedding
// ----------------------------------------------------------------------
/**
 * Parse a JSON number list into a [DoubleArray]; `null` / empty -> null
 * (clears enrollment). Shared by the config parser and the
 * enroll-speaker handler. Mirrors iOS's `__parse_embedding`.
 */
internal fun __parse_embedding(value: Any?): DoubleArray? {
    val list = value as? List<*> ?: return null
    val parsed = list.mapNotNull { (it as? Number)?.toDouble() }
    return if (parsed.isEmpty()) null else parsed.toDoubleArray()
}

// Status encoding
// ----------------------------------------------------------------------
internal fun __encode_status(
    status: ModelStatus
): Map<String, Any> {
    return buildMap {
        put("model_name", status.model_name)
        put("model_type", status.model_type)
        put("status", status.status)
        // Bundle voice inventory (NeuTTS variants). Apps
        // read this from the start_model response to
        // populate voice pickers without scanning the
        // engine cache themselves.
        status.voices?.let { put("voices", it) }
    }
}

// Stream chunk -> event map
// ----------------------------------------------------------------------
/**
 * Serialize an [InferenceStreamChunk] to the map shape
 * expected by Dart's `infer_stream`. Mirrors `__make_event`
 * in iOS `QlipSdkPlugin.startGeneration`.
 */
internal fun __chunk_to_event(
    stream_id: String,
    chunk: InferenceStreamChunk,
): Map<String, Any?> {
    val out = mutableMapOf<String, Any?>(
        "stream_id" to stream_id,
        "kind" to chunk.kind,
        "index" to chunk.index,
        "is_final" to chunk.is_final,
    )
    chunk.delta?.let { out["delta"] = it }
    // Send the raw FloatArray so Flutter's
    // StandardMessageCodec serializes it as a Float32List
    // on the Dart side.
    chunk.audio?.let { out["audio"] = it }
    chunk.sample_rate?.let { out["sample_rate"] = it }
    chunk.time_to_first_token?.let {
        out["time_to_first_token"] = it
    }
    chunk.prompt_tokens?.let { out["prompt_tokens"] = it }
    chunk.generated_tokens?.let {
        out["generated_tokens"] = it
    }
    chunk.tokens_per_second?.let {
        out["tokens_per_second"] = it
    }
    chunk.total_seconds?.let { out["total_seconds"] = it }
    chunk.vision_ms?.let { out["vision_ms"] = it }
    chunk.projector_ms?.let {
        out["projector_ms"] = it
    }
    chunk.prompt_ms?.let { out["prompt_ms"] = it }
    chunk.decode_ms?.let { out["decode_ms"] = it }
    chunk.image_tokens?.let {
        out["image_tokens"] = it
    }
    return out
}

// Error reporting
// ----------------------------------------------------------------------
/**
 * Map an exception onto a Flutter [MethodChannel.Result]
 * error. Mirrors the original `thestage_android_sdk` plugin's
 * `__finish_error`: forward the SDK's pre-recorded symbolic
 * code (INPUT_TOO_LONG / SENTENCE_TOO_LONG / ...) as the
 * PlatformException code so apps branch UI without
 * importing internal exception types.
 */
internal fun __fail(
    result: MethodChannel.Result,
    error: Exception,
) {
    // A bundle-backed model whose files are missing,
    // incomplete or malformed (cache-wipe / partial
    // download / lost-DEK sealed engines). Surface a
    // distinct code so apps can show a friendly "reconnect
    // and reload" UI instead of a raw fault. The
    // user-facing message rides on the exception; the
    // technical cause is logged as diagnostics.
    if (error is ModelManagerError.ModelUnavailable) {
        TheStageAI.record_error(
            "MODEL_UNAVAILABLE: ${error.detail}",
            "MODEL_UNAVAILABLE",
        )
        result.error(
            "MODEL_UNAVAILABLE",
            error.message ?: "Model unavailable",
            null,
        )
        return
    }
    val msg = error.message ?: error.toString()
    val sdk_code = TheStageAI.last_error_code
    if (sdk_code == null) {
        TheStageAI.record_error(msg)
    }
    result.error(
        sdk_code ?: "THESTAGE_SDK_ERROR",
        error.message ?: "Unknown error",
        null,
    )
}

internal fun __fail(
    result: MethodChannel.Result,
    msg: String,
) {
    TheStageAI.record_error(msg)
    result.error("THESTAGE_SDK_ERROR", msg, null)
}

// Stream error payload
// ----------------------------------------------------------------------
/**
 * Build the terminal error event pushed onto the TTS
 * stream channel when a streaming collect throws. Carries
 * the SDK's symbolic `error_code`.
 */
internal fun __stream_error_payload(
    stream_id: String,
    error: Throwable,
): Map<String, Any?> {
    val payload = mutableMapOf<String, Any?>(
        "stream_id" to stream_id,
        "kind" to "final",
        "index" to -1,
        "is_final" to true,
        "error" to (error.message
            ?: error::class.simpleName
            ?: "stream error"),
    )
    TheStageAI.last_error_code?.let {
        payload["error_code"] = it
    }
    return payload
}

// Progress
// ----------------------------------------------------------------------
/**
 * Model download/preparation progress → Dart event. A real fraction
 * (>= 0) rides on `progress`; a negative delivery-layer sentinel
 * becomes a `status`-only event (an AI-pack fetch parked on the
 * network/user) so the app never sees a bogus negative number. A
 * waiting event carries `status` and no `progress`; a progress event
 * carries `progress` and no `status`.
 */
internal fun __load_progress_event(
    model_name: String,
    event: ai.thestage.qlip.utils.LoadProgress,
): Map<String, Any?> {
    val map = mutableMapOf<String, Any?>(
        "model_name" to model_name,
        "model" to event.model,
        "phase" to event.phase.raw_value,
    )
    when (event.fraction) {
        -1.0 -> map["status"] = "waiting_for_wifi"
        -2.0 -> map["status"] = "waiting_for_confirmation"
        else -> map["progress"] = event.fraction
    }
    return map
}

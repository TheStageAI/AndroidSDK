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
        // The voices whose MTP draft is usable (NeuTTS
        // multilingual): an app gates its MTP toggle on it.
        status.mtp_voices?.let { put("mtp_voices", it) }
        // LLM / VLM generation features ("mtp", "thinking"):
        // apps show a switch only for a supported one.
        status.features?.let { f ->
            put("features", f.mapValues { it.value.to_map() })
        }
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
    chunk.stop_reason?.let { out["stop_reason"] = it }
    chunk.vision_ms?.let { out["vision_ms"] = it }
    chunk.projector_ms?.let {
        out["projector_ms"] = it
    }
    chunk.prompt_ms?.let { out["prompt_ms"] = it }
    chunk.decode_ms?.let { out["decode_ms"] = it }
    chunk.image_tokens?.let {
        out["image_tokens"] = it
    }
    // Diarization / multispeaker payloads. Each is a list of plain
    // maps so the standard codec carries them without a custom
    // writer, and each is omitted when absent rather than sent as
    // null — a Dart `containsKey` then distinguishes "this chunk is
    // not about speakers" from "no speakers found".
    chunk.stage_profile?.let { out["stage_profile"] = it }
    chunk.segments?.let { segs ->
        out["segments"] = segs.map { it.to_map() }
    }
    chunk.turns?.let { turns ->
        out["turns"] = turns.map { it.to_map() }
    }
    chunk.voices?.let { voices ->
        out["voices"] = voices.map { it.to_map() }
    }
    // LLM tool streams: `tool_call` / `tool_result` name the
    // tool, and `final` carries the reply's parts. Plain maps and
    // lists, which the standard codec carries as they are.
    chunk.name?.let { out["name"] = it }
    chunk.arguments?.let { out["arguments"] = it }
    chunk.content?.let { out["content"] = it }
    chunk.raw_text?.let { out["raw_text"] = it }
    chunk.final_text?.let { out["final_text"] = it }
    chunk.tool_calls?.let { out["tool_calls"] = it }
    chunk.thinking?.let { out["thinking"] = it }
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
    // CONSUME the code: it describes this failure only. Reading
    // it without clearing made it stick, so after one
    // INSUFFICIENT_STORAGE every later uncoded failure reached
    // the app as a storage error. The coded thrower already
    // recorded its own message, which is why nothing is lost by
    // recording only in the uncoded branch.
    val sdk_code = TheStageAI.take_error_code()
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
    // Consumed, as in __fail: a stale code on a stream error is
    // the same bug reported through a different channel.
    TheStageAI.take_error_code()?.let {
        payload["error_code"] = it
    }
    return payload
}

// Progress
// ----------------------------------------------------------------------
/**
 * Model download/preparation progress → Dart event.
 *
 * `phase` is always present and is the signal. The other two keys
 * are conditional:
 *
 *  - `progress` (0..1) rides along only while a transfer is
 *    measurable. `extracting` and `loading` have no measurable
 *    progress, so they omit it rather than repeat a frozen number.
 *  - `status` marks an AI-pack fetch parked on the network or the
 *    user, which is a delivery state and not progress at all.
 *
 * Both are keyed off [LoadProgress.phase]. They used to be keyed
 * off a negative fraction, which made the `status` branch dead
 * code: the runner clamped the sentinels to 0.0 before they could
 * ever arrive here, so a parked download reached apps as a
 * transfer stuck at 0%.
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
    when (event.phase) {
        ai.thestage.qlip.utils.LoadProgress.Phase
            .WAITING_FOR_WIFI ->
            map["status"] = "waiting_for_wifi"
        ai.thestage.qlip.utils.LoadProgress.Phase
            .WAITING_FOR_CONFIRMATION ->
            map["status"] = "waiting_for_confirmation"
        // Omitted, not sent as null, when this phase has no
        // measurable progress -- so a Dart `containsKey` tells
        // "no progress to report" from "reported as zero".
        else -> event.fraction?.let { map["progress"] = it }
    }
    // Byte counters when the server declared a size. Omitted
    // rather than sent as null, so a Dart `containsKey` is
    // enough to tell "not measured" from "measured as zero".
    event.downloaded_bytes?.let {
        map["downloaded_bytes"] = it
    }
    event.total_bytes?.let { map["total_bytes"] = it }
    return map
}

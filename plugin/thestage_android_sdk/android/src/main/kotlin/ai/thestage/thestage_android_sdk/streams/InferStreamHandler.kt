package ai.thestage.thestage_android_sdk.streams

import ai.thestage.qlip.TheStageAI
import ai.thestage.qlip.models.tts.TTSStreamer
import ai.thestage.thestage_android_sdk.internal.__chunk_to_event
import ai.thestage.thestage_android_sdk.internal.__stream_error_payload
import android.util.Log
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// ----------------------------------------------------------------------
// InferStreamHandler
// ----------------------------------------------------------------------
/**
 * EventChannel stream handler backing the streaming-inference
 * channel (`thestage_android_sdk/tts_stream` — the suffix is
 * legacy; the channel carries EVERY streamed model, not just
 * TTS).
 *
 * **Default (one-shot):** drives [TheStageAI.infer_stream]
 * with the request's `input_json` and forwards each chunk as
 * it arrives; a terminal `is_final` chunk closes the stream.
 * This is the path for local LLM, VLM, and one-shot TTS
 * alike — the model is decided by the SDK, not by the shape
 * of the input. Mirrors iOS `QlipSdkPlugin.startGeneration`,
 * which unconditionally calls `infer_stream(model_name,
 * input_json)`.
 *
 * **Push (opt-in, `input_json["stream_mode"] == "push"`):**
 * incremental-TTS. iOS ships the same capability
 * (`TTSStreamHandler.swift` + `open_tts_streamer`); the only
 * difference is the trigger — Android uses this explicit
 * `stream_mode` flag, iOS enters push when the first request
 * carries no text yet. Dart drives `send` / `finish_stream`;
 * a live [TheStageAI.open_tts_streamer] [TTSStreamer] is
 * opened per `stream_id` and its `output` audio flow collected
 * as each pushed sentence arrives. Reached ONLY via the
 * explicit flag — never inferred from the input — so generic
 * inference (LLM/VLM) can never be misrouted here.
 *
 * Per-stream cancellation: each `stream_id` owns one [Job]
 * looked up + cancelled by `cancel`.
 */
class InferStreamHandler(
    private val __scope: CoroutineScope,
) : EventChannel.StreamHandler {

    // Private Attributes
    // ------------------------------------------------------------------
    private var __event_sink: EventChannel.EventSink? = null

    private val __jobs: ConcurrentHashMap<String, Job> =
        ConcurrentHashMap()

    // Live push-mode streamers, keyed by stream_id. Opened in
    // [start] (push mode), fed by [send], closed by
    // [finish_stream] / [cancel].
    private val __streamers:
        ConcurrentHashMap<String, TTSStreamer> =
            ConcurrentHashMap()

    // EventChannel.StreamHandler
    // ------------------------------------------------------------------
    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink?
    ) {
        __event_sink = events
    }

    override fun onCancel(arguments: Any?) {
        for (s in __streamers.values) {
            try { s.cancel() } catch (_: Throwable) {}
        }
        __streamers.clear()
        for (job in __jobs.values) job.cancel()
        __jobs.clear()
        __event_sink = null
    }

    // Public Methods
    // ------------------------------------------------------------------
    val has_sink: Boolean get() = __event_sink != null

    /**
     * Begin a stream. One-shot generic inference by default —
     * the SAME path for local LLM, VLM, and one-shot TTS (the
     * SDK dispatches by model). Incremental-TTS push mode is
     * entered ONLY when the caller explicitly asks for it via
     * `input_json["stream_mode"] == "push"`; it is never
     * inferred from the input shape, so LLM/VLM requests can't
     * be misrouted into the TTS streamer.
     */
    fun start(
        stream_id: String,
        model_name: String,
        input_json: Map<String, Any?>,
    ) {
        __jobs.remove(stream_id)?.cancel()
        __streamers.remove(stream_id)?.let {
            try { it.cancel() } catch (_: Throwable) {}
        }

        val push =
            (input_json["stream_mode"] as? String) == "push"
        if (push) {
            __start_push(stream_id, model_name)
        } else {
            __start_one_shot(stream_id, model_name, input_json)
        }
    }

    fun send(stream_id: String, text: String) {
        __streamers[stream_id]?.send(text)
    }

    fun finish_stream(stream_id: String) {
        // Flush the buffered tail and close: the collector
        // drains the last sentence's audio then completes.
        __streamers[stream_id]?.finish()
    }

    fun cancel(stream_id: String) {
        __streamers.remove(stream_id)?.let {
            try { it.cancel() } catch (_: Throwable) {}
        }
        __jobs.remove(stream_id)?.cancel()
        val sink = __event_sink ?: return
        try {
            sink.success(
                mapOf(
                    "stream_id" to stream_id,
                    "kind" to "cancelled",
                    "index" to -1,
                    "is_final" to true,
                )
            )
        } catch (_: Throwable) {}
    }

    // Private Methods
    // ------------------------------------------------------------------

    /**
     * Open a live [TTSStreamer] and collect its `output` so each
     * pushed sentence synthesizes as it arrives. Open failures
     * (unknown / non-TTS model) surface as a terminal error event.
     */
    private fun __start_push(
        stream_id: String,
        model_name: String,
    ) {
        val sink = __event_sink ?: return

        val streamer = try {
            TheStageAI.open_tts_streamer(model_name = model_name)
        } catch (e: Exception) {
            try {
                sink.success(
                    __stream_error_payload(stream_id, e)
                )
            } catch (_: Throwable) {}
            return
        }
        __streamers[stream_id] = streamer

        val job = __scope.launch(Dispatchers.Default) {
            try {
                streamer.output.collect { chunk ->
                    val payload =
                        __chunk_to_event(stream_id, chunk)
                    withContext(Dispatchers.Main) {
                        try {
                            sink.success(payload)
                        } catch (_: Throwable) {}
                    }
                }
            } catch (e: Exception) {
                Log.e(
                    TAG,
                    "push[$stream_id] error: ${e.message}"
                )
                withContext(Dispatchers.Main) {
                    try {
                        sink.success(
                            __stream_error_payload(
                                stream_id, e
                            )
                        )
                    } catch (_: Throwable) {}
                }
            } finally {
                __jobs.remove(stream_id)
                __streamers.remove(stream_id)
            }
        }
        __jobs[stream_id] = job
    }

    private fun __start_one_shot(
        stream_id: String,
        model_name: String,
        input_json: Map<String, Any?>,
    ) {
        val sink = __event_sink ?: return

        // Resolve the Flow up-front so gate refusals,
        // unknown-model, and unsupported-streaming errors
        // surface on the channel as a terminal error event.
        val flow = try {
            TheStageAI.infer_stream(
                model_name = model_name,
                input_json = input_json,
            )
        } catch (e: Exception) {
            try {
                sink.success(
                    __stream_error_payload(stream_id, e)
                )
            } catch (_: Throwable) {}
            return
        }

        val job = __scope.launch(Dispatchers.Default) {
            try {
                flow.collect { chunk ->
                    val payload =
                        __chunk_to_event(stream_id, chunk)
                    withContext(Dispatchers.Main) {
                        try {
                            sink.success(payload)
                        } catch (_: Throwable) {}
                    }
                }
            } catch (e: Exception) {
                Log.e(
                    TAG,
                    "stream[$stream_id] error: ${e.message}"
                )
                withContext(Dispatchers.Main) {
                    try {
                        sink.success(
                            __stream_error_payload(
                                stream_id, e
                            )
                        )
                    } catch (_: Throwable) {}
                }
            } finally {
                __jobs.remove(stream_id)
            }
        }
        __jobs[stream_id] = job
    }

    companion object {
        private const val TAG = "InferStreamHandler"
    }
}

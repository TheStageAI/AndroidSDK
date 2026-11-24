package ai.thestage.thestage_android_sdk.streams

import ai.thestage.qlip.models.asr.ASREngine
import ai.thestage.qlip.models.asr.ASRGenerationConfig
import ai.thestage.qlip.models.asr.ASRResult
import ai.thestage.qlip.models.asr.ASRStreamEvent
import ai.thestage.qlip.models.asr.ASRStreamingConfig
import ai.thestage.qlip.models.asr.streaming.ASRStream
import ai.thestage.qlip.models.asr.json
import ai.thestage.thestage_android_sdk.internal.ASRJson
import android.util.Log
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// ----------------------------------------------------------------------
// ASRStreamHandler
// ----------------------------------------------------------------------
/**
 * Push-mode ASR sessions for Dart's `ASRStream`, keyed by
 * `stream_id`. Dart owns the audio and feeds PCM with `send`; each
 * session is an [ASREngine.open_stream] on models already started
 * with `start_model` (`model_name`, and `vad_model_name` when given).
 *
 * Events go out on the shared stream channel as
 * `{stream_id, kind, ...}`: `begin`, `turn` (the turn fields),
 * `partial` (`text`), `termination` (`audio_seconds`, `metrics`?) and
 * `cancelled`. A session that fails to open sends a
 * `THESTAGE_STREAM_ERROR` error event.
 */
class ASRStreamHandler(
    private val __scope: CoroutineScope,
    private val __sink_provider: () -> EventChannel.EventSink?,
) {

    // ------------------------------------------------------------------
    // Private Attributes
    // ------------------------------------------------------------------
    private val __streams: ConcurrentHashMap<String, ASRStream> =
        ConcurrentHashMap()
    private val __jobs: ConcurrentHashMap<String, Job> =
        ConcurrentHashMap()

    // Audio sent before the session finished opening, replayed in
    // order once it is open. [__lock] orders sends against that hand
    // over.
    private val __pending: ConcurrentHashMap<String, MutableList<Any>> =
        ConcurrentHashMap()
    private val __lock = Any()

    // ------------------------------------------------------------------
    // Public Methods
    // ------------------------------------------------------------------
    fun has(stream_id: String): Boolean =
        __streams.containsKey(stream_id) ||
            __pending.containsKey(stream_id)

    /** Opens the session in the background; events follow. */
    @Suppress("UNCHECKED_CAST")
    fun start(
        stream_id: String,
        model_name: String,
        input_json: Map<String, Any?>,
    ) {
        __drop(stream_id)
        val sink = __sink_provider() ?: return
        __pending[stream_id] = mutableListOf()
        __jobs[stream_id] = __scope.launch(Dispatchers.Default) {
            val stream = try {
                val generation = ASRGenerationConfig.from_json(input_json)
                val streaming = ASRStreamingConfig.from_json(
                    (input_json["streaming"] as? Map<String, Any?>)
                        ?: emptyMap()
                )
                val vad = (input_json["vad_model_name"] as? String)
                    ?.takeIf { it.isNotEmpty() }
                ASREngine(stt = model_name, vad = vad)
                    .open_stream(generation, streaming)
            } catch (e: Throwable) {
                Log.e(TAG, "open failed: ${e.message}")
                __pending.remove(stream_id)
                __jobs.remove(stream_id)
                withContext(Dispatchers.Main) {
                    try {
                        sink.error(
                            "THESTAGE_STREAM_ERROR",
                            e.message ?: e::class.simpleName,
                            null,
                        )
                    } catch (_: Throwable) {
                    }
                }
                return@launch
            }
            synchronized(__lock) {
                val queued = __pending.remove(stream_id)
                    ?: run {
                        // Cancelled while it opened.
                        stream.cancel()
                        return@launch
                    }
                for (item in queued) {
                    if (item === FLUSH) stream.flush()
                    else stream.send(item as FloatArray)
                }
                __streams[stream_id] = stream
            }
            __drain(stream_id, stream, sink)
        }
    }

    fun send(stream_id: String, pcm: FloatArray) =
        synchronized(__lock) {
            val stream = __streams[stream_id]
            if (stream != null) stream.send(pcm)
            else __pending[stream_id]?.add(pcm)
        }

    fun flush(stream_id: String) = synchronized(__lock) {
        val stream = __streams[stream_id]
        if (stream != null) stream.flush()
        else __pending[stream_id]?.add(FLUSH)
    }

    /** Ends the session and returns its final result. */
    suspend fun close(stream_id: String): ASRResult {
        __await_open(stream_id)
        val stream = __streams[stream_id] ?: return ASRResult.empty
        val result = stream.close()
        // The drain ends on its own once the stream's flows close;
        // the TERMINATION it forwards is the last event.
        __jobs.remove(stream_id)?.join()
        __streams.remove(stream_id)
        return result
    }

    /** Abandons the session; sends `cancelled`. */
    fun cancel(stream_id: String) {
        __drop(stream_id)
        val sink = __sink_provider() ?: return
        __scope.launch(Dispatchers.Main) {
            try {
                sink.success(
                    mapOf(
                        "stream_id" to stream_id,
                        "kind" to "cancelled",
                        "index" to -1,
                        "is_final" to true,
                    )
                )
            } catch (_: Throwable) {
            }
        }
    }

    /** Cancels every session (the stream channel went away). */
    fun cancel_all() {
        for (id in __streams.keys + __pending.keys) __drop(id)
    }

    // ------------------------------------------------------------------
    // Private Methods
    // ------------------------------------------------------------------
    private fun __drop(stream_id: String) {
        val stream = synchronized(__lock) {
            __pending.remove(stream_id)
            __streams.remove(stream_id)
        }
        __jobs.remove(stream_id)?.cancel()
        stream?.cancel()
    }

    private suspend fun __await_open(stream_id: String) {
        if (__streams.containsKey(stream_id)) return
        // Still opening: wait for the open to land (or fail).
        while (__pending.containsKey(stream_id) &&
            !__streams.containsKey(stream_id)
        ) {
            kotlinx.coroutines.delay(5)
        }
    }

    private suspend fun __drain(
        stream_id: String,
        stream: ASRStream,
        sink: EventChannel.EventSink,
    ) = coroutineScope {
        launch {
            stream.events.collect { event ->
                __emit(sink, __event(event, stream_id))
            }
        }
        launch {
            stream.partials.collect { text ->
                __emit(
                    sink,
                    mapOf(
                        "stream_id" to stream_id,
                        "kind" to "partial",
                        "text" to text,
                        "is_final" to false,
                    ),
                )
            }
        }
    }

    private suspend fun __emit(
        sink: EventChannel.EventSink,
        payload: Map<String, Any?>,
    ) = withContext(Dispatchers.Main) {
        try {
            sink.success(payload)
        } catch (_: Throwable) {
        }
    }

    private fun __event(
        event: ASRStreamEvent,
        stream_id: String,
    ): Map<String, Any?> = when (event) {
        ASRStreamEvent.BEGIN -> mapOf(
            "stream_id" to stream_id,
            "kind" to "begin",
            "is_final" to false,
        )
        is ASRStreamEvent.TURN -> ASRJson.turn(event.turn).apply {
            put("stream_id", stream_id)
            put("kind", "turn")
        }
        is ASRStreamEvent.TERMINATION -> {
            val payload = linkedMapOf<String, Any?>(
                "stream_id" to stream_id,
                "kind" to "termination",
                "audio_seconds" to event.audio_seconds,
                "is_final" to true,
            )
            event.metrics?.let { payload["metrics"] = it.json() }
            payload
        }
    }

    companion object {
        private const val TAG = "ASRStreamHandler"

        /** Queue marker for a flush sent while the session opens. */
        private val FLUSH = Any()
    }
}

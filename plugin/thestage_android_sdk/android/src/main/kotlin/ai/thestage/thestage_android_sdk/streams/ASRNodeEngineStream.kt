package ai.thestage.thestage_android_sdk.streams

import ai.thestage.qlip.models.asr.ASREngine
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// ----------------------------------------------------------------------
// ASRNodeEngineStream
// ----------------------------------------------------------------------
/**
 * One output flow of a microphone-mode [ASREngine] exposed as a
 * Flutter broadcast stream. Same shape as
 * [VoiceAgentBroadcastStream]: Dart may subscribe before or after
 * `asr_engine.start`, so the sink and the engine arrive
 * independently and whichever lands second opens the connector.
 *
 * [port] maps the engine to the flow this channel carries, already
 * in codec types (`String`, `Double`, `Map`).
 */
class ASRNodeEngineStream(
    private val __scope: CoroutineScope,
    private val __engine_provider: () -> ASREngine?,
    private val __port: (ASREngine) -> Flow<Any>,
) : EventChannel.StreamHandler {

    // ------------------------------------------------------------------
    // Private Attributes
    // ------------------------------------------------------------------
    private var __sink: EventChannel.EventSink? = null
    private var __job: Job? = null

    // ------------------------------------------------------------------
    // Public Methods
    // ------------------------------------------------------------------
    /** The engine was created; reopen the connector if Dart listens. */
    fun bind(engine: ASREngine) {
        __job?.cancel()
        __job = null
        if (__sink != null) __open_connector(engine)
    }

    fun unbind() {
        __job?.cancel()
        __job = null
    }

    // ------------------------------------------------------------------
    // EventChannel.StreamHandler
    // ------------------------------------------------------------------
    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink?,
    ) {
        __sink = events
        __engine_provider()?.let { __open_connector(it) }
    }

    override fun onCancel(arguments: Any?) {
        __job?.cancel()
        __job = null
        __sink = null
    }

    // ------------------------------------------------------------------
    // Private Methods
    // ------------------------------------------------------------------
    private fun __open_connector(engine: ASREngine) {
        __job?.cancel()
        val sink = __sink
        __job = __scope.launch(Dispatchers.Default) {
            __port(engine).collect { value ->
                withContext(Dispatchers.Main) {
                    try {
                        sink?.success(value)
                    } catch (_: Throwable) {
                    }
                }
            }
        }
    }
}

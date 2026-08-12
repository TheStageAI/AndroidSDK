package ai.thestage.thestage_android_sdk.streams

import ai.thestage.qlip.voice_agent.TheStageVoiceAgent
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// ----------------------------------------------------------------------
// VoiceAgentBroadcastStream
// ----------------------------------------------------------------------
/**
 * EventChannel stream handler that taps one of the voice
 * agent's typed flows ([TheStageVoiceAgent.llm_deltas],
 * `transcripts`, or `vad_probabilities`) and forwards each
 * value to the Dart broadcast stream. Mirrors Swift's
 * `VoiceAgentBroadcastStream`.
 *
 * The agent may not exist yet when Dart starts listening,
 * so [VoiceAgentStateStream] registers each broadcast as a
 * "tap" and calls [bind] once the agent starts (and
 * [unbind] on stop). The connector (a flow-collect [Job])
 * is created only while a Dart sink is attached AND an
 * agent is bound.
 */
class VoiceAgentBroadcastStream(
    private val scope: CoroutineScope,
    private val agent_provider: () -> TheStageVoiceAgent?,
    private val port:
        (TheStageVoiceAgent) -> Flow<Any>,
) : EventChannel.StreamHandler {

    // Private Attributes
    // ------------------------------------------------------------------
    private var __sink: EventChannel.EventSink? = null
    private var __job: Job? = null

    // Public Methods
    // ------------------------------------------------------------------
    fun bind(agent: TheStageVoiceAgent) {
        __job?.cancel()
        __job = null
        if (__sink != null) {
            __open_connector(agent)
        }
    }

    fun unbind() {
        __job?.cancel()
        __job = null
    }

    // EventChannel.StreamHandler
    // ------------------------------------------------------------------
    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink?
    ) {
        __sink = events
        agent_provider()?.let { __open_connector(it) }
    }

    override fun onCancel(arguments: Any?) {
        __job?.cancel()
        __job = null
        __sink = null
    }

    // Private Methods
    // ------------------------------------------------------------------
    private fun __open_connector(agent: TheStageVoiceAgent) {
        __job?.cancel()
        val sink = __sink
        __job = scope.launch(Dispatchers.Default) {
            port(agent).collect { value ->
                withContext(Dispatchers.Main) {
                    try {
                        sink?.success(value)
                    } catch (_: Throwable) {}
                }
            }
        }
    }
}

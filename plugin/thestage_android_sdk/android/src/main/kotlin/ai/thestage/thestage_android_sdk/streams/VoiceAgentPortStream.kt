package ai.thestage.thestage_android_sdk.streams

import ai.thestage.qlip.voice_agent.TheStageVoiceAgent
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

// ----------------------------------------------------------------------
// VoiceAgentPortStream
// ----------------------------------------------------------------------
/**
 * EventChannel stream handler backing `voice_agent_ports`. Multiplexes
 * every named agent port onto one Dart sink as `{port, value}` maps:
 * the built-in channels (`llm.delta`, `transcripts.final`,
 * `vad.probability`) plus any custom node port registered via
 * [register_node_port_forward]. Mirrors Qlip.Swift's
 * `VoiceAgentPortStream`.
 */
class VoiceAgentPortStream(
    private val scope: CoroutineScope,
    private val agent_provider: () -> TheStageVoiceAgent?,
) : EventChannel.StreamHandler {

    // Private Attributes
    // ------------------------------------------------------------------
    private var __sink: EventChannel.EventSink? = null
    private val __jobs: MutableList<Job> = mutableListOf()

    // Public Methods
    // ------------------------------------------------------------------
    fun bind(agent: TheStageVoiceAgent) {
        if (__sink != null) __bind(agent)
    }

    fun unbind() {
        __teardown()
    }

    fun register_node_port_forward(
        node: FlutterBridgeNode,
        port: String,
    ) {
        val sink = __sink ?: return
        node.ensure_port_forward(port) { payload ->
            __emit(payload)
        }
    }

    // EventChannel.StreamHandler
    // ------------------------------------------------------------------
    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink?,
    ) {
        __sink = events
        agent_provider()?.let { __bind(it) }
    }

    override fun onCancel(arguments: Any?) {
        __teardown()
        __sink = null
    }

    // Private Methods
    // ------------------------------------------------------------------
    private fun __bind(agent: TheStageVoiceAgent) {
        __teardown()
        __connect(agent.llm_deltas, "llm.delta")
        __connect(agent.transcripts, "transcripts.final")
        __connect(agent.vad_probabilities, "vad.probability")
    }

    private fun __connect(flow: Flow<Any>, name: String) {
        __jobs.add(
            scope.launch(Dispatchers.Default) {
                flow.collect { value ->
                    __emit(mapOf("port" to name, "value" to value))
                }
            }
        )
    }

    private fun __emit(payload: Map<String, Any?>) {
        val sink = __sink ?: return
        scope.launch(Dispatchers.Main) {
            try {
                sink.success(payload)
            } catch (_: Throwable) {}
        }
    }

    private fun __teardown() {
        for (j in __jobs) j.cancel()
        __jobs.clear()
    }
}

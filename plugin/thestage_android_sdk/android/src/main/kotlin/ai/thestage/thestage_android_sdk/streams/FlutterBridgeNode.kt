package ai.thestage.thestage_android_sdk.streams

import ai.thestage.qlip.voice_agent.graph.AgentChannel
import ai.thestage.qlip.voice_agent.graph.AgentEvent
import ai.thestage.qlip.voice_agent.graph.RequestSource
import ai.thestage.qlip.voice_agent.graph.TheStageAgentNode
import ai.thestage.qlip.voice_agent.graph.TheStageAgentState
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

// ----------------------------------------------------------------------
// FlutterBridgeNode
// ----------------------------------------------------------------------
/**
 * Custom agent node that forwards its lifecycle hooks + the shared
 * event bus to Dart over [MethodChannels.VOICE_AGENT_NODES]. Mirrors
 * Qlip.Swift's `FlutterBridgeNode`, adapted to the Android node
 * discipline (extends [TheStageAgentNode], collects on the inherited
 * serialized [scope]).
 *
 * All `MethodChannel.invokeMethod` calls are marshalled to the main
 * thread — the Flutter platform channels are main-thread only.
 */
class FlutterBridgeNode(
    id: String,
    private val __run_when_states: Set<TheStageAgentState>,
    private val __channel: MethodChannel,
) : TheStageAgentNode(id) {

    // Public Attributes
    // ------------------------------------------------------------------
    override val run_when: Set<TheStageAgentState> = __run_when_states

    val is_gate_open: Boolean
        get() = __run_when_states.isEmpty() ||
            __run_when_states.contains(__current_state)

    // Private Attributes
    // ------------------------------------------------------------------
    @Volatile
    private var __current_state: TheStageAgentState =
        TheStageAgentState.IDLE
    private var __event_job: Job? = null
    private val __port_forwarders: MutableMap<String, Job> =
        mutableMapOf()
    private val __main = Handler(Looper.getMainLooper())

    // Lifecycle
    // ------------------------------------------------------------------
    override suspend fun start() {
        __invoke(
            "voice_agent.node_on_start",
            mapOf(
                "id" to id,
                "state" to __current_state.raw,
                "is_gate_open" to is_gate_open,
            ),
        )
        val stream = subscribe() ?: return
        __event_job = scope.launch {
            stream.collect { event -> __handle_event(event) }
        }
    }

    override suspend fun stop() {
        __event_job?.cancel()
        __event_job = null
        for ((_, job) in __port_forwarders) job.cancel()
        __port_forwarders.clear()
        __invoke(
            "voice_agent.node_on_stop",
            mapOf(
                "id" to id,
                "state" to __current_state.raw,
                "is_gate_open" to is_gate_open,
            ),
        )
        super.stop()
    }

    // Port I/O
    // ------------------------------------------------------------------
    fun send_port(name: String, value: String) {
        make_port<String>(name).send(value)
    }

    /** Publish a subset of bus events from Dart (`USER_REQUEST`
     *  today). Routes through the inherited [publish] so the event
     *  lands on the shared orchestrator bus. */
    fun publish_bus_event(event: Map<String, Any?>) {
        val kind = (event["kind"] as? String)?.uppercase() ?: ""
        when (kind) {
            "USER_REQUEST" -> {
                val text = event["text"] as? String ?: ""
                val source = when (
                    (event["source"] as? String)?.lowercase()
                ) {
                    "speech" -> RequestSource.SPEECH
                    "system" -> RequestSource.SYSTEM
                    else -> RequestSource.TEXT
                }
                publish(AgentEvent.UserRequest(text, source))
            }
            else -> {}
        }
    }

    fun ensure_port_forward(
        name: String,
        sink: (Map<String, Any?>) -> Unit,
    ) {
        if (__port_forwarders.containsKey(name)) return
        val channel: AgentChannel<String> = make_port(name)
        __port_forwarders[name] = channel.collect(scope) { value ->
            sink(
                mapOf(
                    "port" to "$id.$name",
                    "value" to value,
                ),
            )
        }
    }

    // Private Methods
    // ------------------------------------------------------------------
    private fun __handle_event(event: AgentEvent) {
        when (event) {
            is AgentEvent.State -> {
                __current_state = event.state
                __invoke(
                    "voice_agent.node_on_state",
                    mapOf(
                        "id" to id,
                        "state" to event.state.raw,
                        "is_gate_open" to is_gate_open,
                    ),
                )
            }
            else -> {
                __invoke(
                    "voice_agent.node_on_event",
                    mapOf(
                        "id" to id,
                        "state" to __current_state.raw,
                        "is_gate_open" to is_gate_open,
                        "event" to __serialize_event(event),
                    ),
                )
            }
        }
    }

    private fun __invoke(method: String, args: Map<String, Any?>) {
        __main.post {
            try {
                __channel.invokeMethod(method, args)
            } catch (_: Throwable) {}
        }
    }

    private fun __serialize_event(
        event: AgentEvent,
    ): Map<String, Any?> = when (event) {
        is AgentEvent.SpeechStarted ->
            mapOf("kind" to "SPEECH_STARTED", "prob" to event.prob)
        is AgentEvent.SpeechEnded ->
            mapOf(
                "kind" to "SPEECH_ENDED",
                "silence_ms" to event.silence_ms,
            )
        is AgentEvent.BargeIn ->
            mapOf("kind" to "BARGE_IN", "prob" to event.prob)
        is AgentEvent.WakeWordDetected ->
            mapOf("kind" to "WAKE_WORD_DETECTED", "prob" to event.prob)
        is AgentEvent.SpeakerVerified ->
            mapOf(
                "kind" to "SPEAKER_VERIFIED",
                "similarity" to event.similarity,
            )
        is AgentEvent.SpeakerRejected ->
            mapOf(
                "kind" to "SPEAKER_REJECTED",
                "similarity" to event.similarity,
            )
        is AgentEvent.SpeechOnset ->
            mapOf("kind" to "SPEECH_ONSET", "prob" to event.prob)
        is AgentEvent.TurnStartAccepted ->
            mapOf("kind" to "TURN_START_ACCEPTED")
        is AgentEvent.UserRequestPartial ->
            mapOf("kind" to "USER_REQUEST_PARTIAL", "text" to event.text)
        is AgentEvent.UserRequest ->
            mapOf(
                "kind" to "USER_REQUEST",
                "text" to event.text,
                "source" to event.source.name.lowercase(),
            )
        is AgentEvent.ResponseStarted ->
            mapOf("kind" to "RESPONSE_STARTED")
        is AgentEvent.ResponseDone ->
            mapOf(
                "kind" to "RESPONSE_DONE",
                "text" to event.text,
                "reason" to event.reason.name.lowercase(),
            )
        is AgentEvent.SynthesisDone ->
            mapOf(
                "kind" to "SYNTHESIS_DONE",
                "reason" to event.reason.name.lowercase(),
            )
        is AgentEvent.PlaybackStarted ->
            mapOf("kind" to "PLAYBACK_STARTED")
        is AgentEvent.PlaybackEnded ->
            mapOf(
                "kind" to "PLAYBACK_ENDED",
                "reason" to event.reason.name.lowercase(),
            )
        is AgentEvent.State ->
            mapOf("kind" to "STATE", "state" to event.state.raw)
        is AgentEvent.Error ->
            mapOf("kind" to "ERROR", "message" to event.message)
    }
}

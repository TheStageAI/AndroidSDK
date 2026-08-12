package ai.thestage.thestage_android_sdk

import ai.thestage.qlip.TheStageAI
import ai.thestage.qlip.audio.AudioStreamPlayer
import ai.thestage.thestage_android_sdk.handlers.__handle_audio_drain
import ai.thestage.thestage_android_sdk.handlers.__handle_audio_enqueue
import ai.thestage.thestage_android_sdk.handlers.__handle_audio_pause
import ai.thestage.thestage_android_sdk.handlers.__handle_audio_resume
import ai.thestage.thestage_android_sdk.handlers.__handle_audio_start
import ai.thestage.thestage_android_sdk.handlers.__handle_audio_stop
import ai.thestage.thestage_android_sdk.handlers.__handle_bundled_engine_path
import ai.thestage.thestage_android_sdk.handlers.__handle_check_model_availability
import ai.thestage.thestage_android_sdk.handlers.__handle_finish_stream
import ai.thestage.thestage_android_sdk.handlers.__handle_infer
import ai.thestage.thestage_android_sdk.handlers.__handle_initialize
import ai.thestage.thestage_android_sdk.handlers.__handle_list_components
import ai.thestage.thestage_android_sdk.handlers.__handle_load_components
import ai.thestage.thestage_android_sdk.handlers.__handle_memory_footprint
import ai.thestage.thestage_android_sdk.handlers.__handle_prefetch_model
import ai.thestage.thestage_android_sdk.handlers.__handle_send_stream
import ai.thestage.thestage_android_sdk.handlers.__handle_start_model
import ai.thestage.thestage_android_sdk.handlers.__handle_start_stream
import ai.thestage.thestage_android_sdk.handlers.__handle_stop_model
import ai.thestage.thestage_android_sdk.handlers.__handle_stop_stream
import ai.thestage.thestage_android_sdk.handlers.__handle_unload_components
import ai.thestage.thestage_android_sdk.handlers.__handle_voice_agent_clear_history
import ai.thestage.thestage_android_sdk.handlers.__handle_voice_agent_begin_listening
import ai.thestage.thestage_android_sdk.handlers.__handle_voice_agent_enroll_speaker
import ai.thestage.thestage_android_sdk.handlers.__handle_voice_agent_interrupt
import ai.thestage.thestage_android_sdk.handlers.__handle_voice_agent_say
import ai.thestage.thestage_android_sdk.handlers.__handle_voice_agent_send_node_port
import ai.thestage.thestage_android_sdk.handlers.__handle_voice_agent_publish_node_event
import ai.thestage.thestage_android_sdk.handlers.__handle_voice_agent_send_request
import ai.thestage.thestage_android_sdk.handlers.__handle_screen_recorder_is_recording
import ai.thestage.thestage_android_sdk.handlers.__handle_screen_recorder_start
import ai.thestage.thestage_android_sdk.handlers.__handle_screen_recorder_stop
import ai.thestage.thestage_android_sdk.handlers.__handle_voice_agent_set_voice
import ai.thestage.thestage_android_sdk.handlers.__handle_voice_agent_start
import ai.thestage.thestage_android_sdk.handlers.__handle_voice_agent_stop
import ai.thestage.thestage_android_sdk.handlers.__handle_voice_agent_update_interrupt_config
import ai.thestage.thestage_android_sdk.internal.MethodChannels
import ai.thestage.thestage_android_sdk.internal.MethodRoute
import ai.thestage.thestage_android_sdk.streams.DeveloperLogStream
import ai.thestage.thestage_android_sdk.streams.InferStreamHandler
import ai.thestage.thestage_android_sdk.streams.VoiceAgentBroadcastStream
import ai.thestage.thestage_android_sdk.streams.VoiceAgentPortStream
import ai.thestage.thestage_android_sdk.streams.ScreenDemoRecorder
import ai.thestage.thestage_android_sdk.streams.VoiceAgentStateStream
import android.app.Activity
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

// ----------------------------------------------------------------------
// TheStageFlutterPlugin
// ----------------------------------------------------------------------
/**
 * FlutterPlugin entry point for the TheStage AI Android SDK.
 *
 * Mirrors Swift's `TheStageFlutterPlugin`: it owns the
 * channel wiring + route dispatch and delegates each route
 * to a handler extension (in `handlers/`) wired onto the new
 * SDK APIs ([ai.thestage.qlip.TheStageAI],
 * [ai.thestage.qlip.voice_agent.TheStageVoiceAgent],
 * [ai.thestage.qlip.audio.AudioStreamPlayer], and the
 * TTS streamer). The four voice-agent EventChannels and the
 * push/one-shot TTS stream channel are set up here.
 */
class TheStageFlutterPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    // Internal Attributes (shared with handler extensions)
    // ------------------------------------------------------------------
    internal var __app_context: android.content.Context? = null
    internal var __progress_sink: EventChannel.EventSink? = null

    /** Current foreground Activity (null while detached). Used by the
     *  screen recorder to launch the capture-consent dialog. */
    internal var __activity: Activity? = null

    internal var __stream_handler: InferStreamHandler? = null
    internal var __voice_agent_handler: VoiceAgentStateStream? = null

    internal val __audio_players:
        ConcurrentHashMap<String, AudioStreamPlayer> =
            ConcurrentHashMap()

    internal val __scope = CoroutineScope(
        SupervisorJob() + Dispatchers.Main
    )

    // Private Attributes
    // ------------------------------------------------------------------
    private lateinit var __method_channel: MethodChannel
    private lateinit var __progress_channel: EventChannel
    private lateinit var __tts_channel: EventChannel
    private lateinit var __va_events_channel: EventChannel
    private lateinit var __va_llm_deltas_channel: EventChannel
    private lateinit var __va_transcripts_channel: EventChannel
    private lateinit var __va_vad_probs_channel: EventChannel
    private lateinit var __va_ports_channel: EventChannel
    private lateinit var __va_nodes_channel: MethodChannel
    private lateinit var __logs_channel: EventChannel

    private var __activity_binding: ActivityPluginBinding? = null

    // Relays the screen-capture consent result to the recorder.
    private val __activity_result_listener =
        PluginRegistry.ActivityResultListener {
            requestCode, resultCode, data ->
            ScreenDemoRecorder.onActivityResult(
                requestCode, resultCode, data
            )
        }

    // FlutterPlugin
    // ------------------------------------------------------------------
    override fun onAttachedToEngine(
        binding: FlutterPlugin.FlutterPluginBinding
    ) {
        __app_context = binding.applicationContext

        __method_channel = MethodChannel(
            binding.binaryMessenger, MethodChannels.MAIN
        )
        __method_channel.setMethodCallHandler(this)

        __progress_channel = EventChannel(
            binding.binaryMessenger, MethodChannels.PROGRESS
        )
        __progress_channel.setStreamHandler(this)

        val stream_handler = InferStreamHandler(__scope)
        __tts_channel = EventChannel(
            binding.binaryMessenger, MethodChannels.TTS_STREAM
        )
        __tts_channel.setStreamHandler(stream_handler)
        __stream_handler = stream_handler

        // Voice-agent state stream backs the main
        // `voice_agent_events` channel and owns the agent;
        // the three broadcast streams tap its flows.
        val va_handler = VoiceAgentStateStream(__scope)
        __va_events_channel = EventChannel(
            binding.binaryMessenger,
            MethodChannels.VOICE_AGENT_EVENTS,
        )
        __va_events_channel.setStreamHandler(va_handler)
        __voice_agent_handler = va_handler

        val llm_deltas = VoiceAgentBroadcastStream(
            scope = __scope,
            agent_provider = { va_handler.agent },
            port = { agent -> agent.llm_deltas },
        )
        __va_llm_deltas_channel = EventChannel(
            binding.binaryMessenger,
            MethodChannels.VOICE_AGENT_LLM_DELTAS,
        )
        __va_llm_deltas_channel.setStreamHandler(llm_deltas)
        va_handler.register_tap(llm_deltas)

        val transcripts = VoiceAgentBroadcastStream(
            scope = __scope,
            agent_provider = { va_handler.agent },
            port = { agent -> agent.transcripts },
        )
        __va_transcripts_channel = EventChannel(
            binding.binaryMessenger,
            MethodChannels.VOICE_AGENT_TRANSCRIPTS,
        )
        __va_transcripts_channel.setStreamHandler(transcripts)
        va_handler.register_tap(transcripts)

        val vad_probs = VoiceAgentBroadcastStream(
            scope = __scope,
            agent_provider = { va_handler.agent },
            port = { agent -> agent.vad_probabilities },
        )
        __va_vad_probs_channel = EventChannel(
            binding.binaryMessenger,
            MethodChannels.VOICE_AGENT_VAD_PROBABILITIES,
        )
        __va_vad_probs_channel.setStreamHandler(vad_probs)
        va_handler.register_tap(vad_probs)

        // Port multiplexer: one `{port, value}` stream carrying the
        // built-in channels plus any custom node port. Bound to the
        // agent over its lifetime by the state stream.
        val port_stream = VoiceAgentPortStream(
            __scope,
            { va_handler.agent },
        )
        __va_ports_channel = EventChannel(
            binding.binaryMessenger,
            MethodChannels.VOICE_AGENT_PORTS,
        )
        __va_ports_channel.setStreamHandler(port_stream)

        // Custom-node lifecycle bridge (MethodChannel): FlutterBridgeNode
        // instances forward on_start / on_state / on_event / on_stop to
        // Dart over this channel.
        __va_nodes_channel = MethodChannel(
            binding.binaryMessenger,
            MethodChannels.VOICE_AGENT_NODES,
        )
        va_handler.configure(__va_nodes_channel, port_stream)

        // Developer-log bridge: stream the SDK diagnostics ring to
        // `flutter run` (mirrors the Apple SDK's `logs` channel).
        __logs_channel = EventChannel(
            binding.binaryMessenger, MethodChannels.LOGS
        )
        __logs_channel.setStreamHandler(DeveloperLogStream())
    }

    override fun onDetachedFromEngine(
        binding: FlutterPlugin.FlutterPluginBinding
    ) {
        // Engine teardown = app quit (graceful exit /
        // swipe-away destroys the activity + engine). Close
        // all active models so the SDK releases its
        // NPU/Hexagon (QNN) contexts. The app's foreground
        // service keeps the process alive after the UI
        // closes, so without this a context stays allocated
        // and the next launch's Start fails to create a
        // fresh one ("Failed to create context from binary.
        // Error code: 1002"). Best-effort — a hard OS kill
        // may skip this; backgrounding never reaches here,
        // so background work keeps running.
        try {
            TheStageAI.stop_all_models()
        } catch (e: Exception) {
            Log.w(
                "TheStageFlutterPlugin",
                "stop_all_models on detach failed: " +
                    "${e.message}"
            )
        }
        __method_channel.setMethodCallHandler(null)
        __progress_channel.setStreamHandler(null)
        __tts_channel.setStreamHandler(null)
        __va_events_channel.setStreamHandler(null)
        __va_llm_deltas_channel.setStreamHandler(null)
        __va_transcripts_channel.setStreamHandler(null)
        __va_vad_probs_channel.setStreamHandler(null)
        __va_ports_channel.setStreamHandler(null)
        __va_nodes_channel.setMethodCallHandler(null)
        __logs_channel.setStreamHandler(null)

        for (p in __audio_players.values) {
            try { p.stop() } catch (_: Throwable) {}
        }
        __audio_players.clear()
        __scope.cancel()
    }

    // ActivityAware
    // ------------------------------------------------------------------
    override fun onAttachedToActivity(
        binding: ActivityPluginBinding
    ) {
        __attach_activity(binding)
    }

    override fun onReattachedToActivityForConfigChanges(
        binding: ActivityPluginBinding
    ) {
        __attach_activity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        __detach_activity()
    }

    override fun onDetachedFromActivity() {
        __detach_activity()
    }

    private fun __attach_activity(binding: ActivityPluginBinding) {
        __detach_activity()
        __activity_binding = binding
        __activity = binding.activity
        binding.addActivityResultListener(__activity_result_listener)
    }

    private fun __detach_activity() {
        __activity_binding?.removeActivityResultListener(
            __activity_result_listener
        )
        __activity_binding = null
        __activity = null
    }

    // EventChannel.StreamHandler (progress)
    // ------------------------------------------------------------------
    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink?
    ) {
        __progress_sink = events
    }

    override fun onCancel(arguments: Any?) {
        __progress_sink = null
    }

    // MethodChannel.MethodCallHandler
    // ------------------------------------------------------------------
    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result
    ) {
        when (call.method) {
            // Lifecycle
            MethodRoute.INITIALIZE ->
                __handle_initialize(call, result)
            MethodRoute.START_MODEL ->
                __handle_start_model(call, result)
            MethodRoute.STOP_MODEL ->
                __handle_stop_model(call, result)

            // Components
            MethodRoute.LIST_COMPONENTS ->
                __handle_list_components(call, result)
            MethodRoute.LOAD_COMPONENTS ->
                __handle_load_components(call, result)
            MethodRoute.UNLOAD_COMPONENTS ->
                __handle_unload_components(call, result)
            MethodRoute.BUNDLED_ENGINE_PATH ->
                __handle_bundled_engine_path(call, result)
            MethodRoute.MEMORY_FOOTPRINT ->
                __handle_memory_footprint(call, result)

            // Inference / streaming
            MethodRoute.INFER ->
                __handle_infer(call, result)
            MethodRoute.START_STREAM ->
                __handle_start_stream(call, result)
            MethodRoute.SEND ->
                __handle_send_stream(call, result)
            MethodRoute.FINISH_STREAM ->
                __handle_finish_stream(call, result)
            MethodRoute.STOP_STREAM ->
                __handle_stop_stream(call, result)

            // Audio
            MethodRoute.AUDIO_START ->
                __handle_audio_start(call, result)
            MethodRoute.AUDIO_ENQUEUE ->
                __handle_audio_enqueue(call, result)
            MethodRoute.AUDIO_PAUSE ->
                __handle_audio_pause(call, result)
            MethodRoute.AUDIO_RESUME ->
                __handle_audio_resume(call, result)
            MethodRoute.AUDIO_DRAIN ->
                __handle_audio_drain(call, result)
            MethodRoute.AUDIO_STOP ->
                __handle_audio_stop(call, result)

            // Voice agent
            MethodRoute.VOICE_AGENT_START ->
                __handle_voice_agent_start(call, result)
            MethodRoute.VOICE_AGENT_STOP ->
                __handle_voice_agent_stop(call, result)
            MethodRoute.VOICE_AGENT_INTERRUPT ->
                __handle_voice_agent_interrupt(call, result)
            MethodRoute.VOICE_AGENT_SAY ->
                __handle_voice_agent_say(call, result)
            MethodRoute.VOICE_AGENT_SET_VOICE ->
                __handle_voice_agent_set_voice(call, result)
            MethodRoute.VOICE_AGENT_CLEAR_HISTORY ->
                __handle_voice_agent_clear_history(call, result)
            MethodRoute.VOICE_AGENT_UPDATE_INTERRUPT_CONFIG ->
                __handle_voice_agent_update_interrupt_config(
                    call, result
                )
            MethodRoute.VOICE_AGENT_ENROLL_SPEAKER ->
                __handle_voice_agent_enroll_speaker(call, result)
            MethodRoute.VOICE_AGENT_BEGIN_LISTENING ->
                __handle_voice_agent_begin_listening(call, result)
            MethodRoute.VOICE_AGENT_SEND_NODE_PORT ->
                __handle_voice_agent_send_node_port(call, result)
            MethodRoute.VOICE_AGENT_PUBLISH_NODE_EVENT ->
                __handle_voice_agent_publish_node_event(call, result)
            MethodRoute.VOICE_AGENT_SEND_REQUEST ->
                __handle_voice_agent_send_request(call, result)
            MethodRoute.SCREEN_RECORDER_IS_RECORDING ->
                __handle_screen_recorder_is_recording(call, result)
            MethodRoute.SCREEN_RECORDER_START ->
                __handle_screen_recorder_start(call, result)
            MethodRoute.SCREEN_RECORDER_STOP ->
                __handle_screen_recorder_stop(call, result)

            // Android-only routes
            MethodRoute.ANDROID_PREFETCH_MODEL ->
                __handle_prefetch_model(call, result)
            MethodRoute.ANDROID_CHECK_MODEL_AVAILABILITY ->
                __handle_check_model_availability(call, result)

            else -> result.notImplemented()
        }
    }

    internal companion object {
        const val TAG = "TheStageFlutterPlugin"
    }
}

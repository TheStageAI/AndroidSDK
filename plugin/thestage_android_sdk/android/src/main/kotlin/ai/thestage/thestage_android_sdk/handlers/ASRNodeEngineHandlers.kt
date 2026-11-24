package ai.thestage.thestage_android_sdk.handlers

import ai.thestage.qlip.models.asr.ASREngine
import ai.thestage.qlip.utils.LoadProgress
import ai.thestage.qlip.utils.LoadProgressHandler
import ai.thestage.qlip.voice_agent.TheStageAgentConfig
import ai.thestage.qlip.voice_agent.graph.TurnConfig
import ai.thestage.thestage_android_sdk.TheStageFlutterPlugin
import ai.thestage.thestage_android_sdk.internal.ASRJson
import ai.thestage.thestage_android_sdk.internal.__load_progress_event
import ai.thestage.thestage_android_sdk.streams.ASRNodeEngineStream
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

// ----------------------------------------------------------------------
// ASRNodeEngineHandlers
// ----------------------------------------------------------------------
/**
 * Bridges the microphone-mode [ASREngine] (`ASREngine(config)`) to
 * Dart's `TSASREngine`. The engine owns the whole session natively:
 * audio capture, VAD, turn policy and one persistent decoder stream.
 * Dart passes model repo ids as strings and reads the typed streams.
 *
 * Model loading is the engine's: it resolves `stt` / `vad` itself,
 * records what it loaded and releases it on `stop()`.
 */
class ASRNodeEngineHandlers(
    private val __scope: CoroutineScope,
) {

    // ------------------------------------------------------------------
    // Private Attributes
    // ------------------------------------------------------------------
    @Volatile
    private var __engine: ASREngine? = null
    private val __lock = Mutex()

    // ------------------------------------------------------------------
    // Public Attributes
    // ------------------------------------------------------------------
    val turns = ASRNodeEngineStream(__scope, { __engine }) { engine ->
        engine.turns.map { ASRJson.turn(it) }
    }
    val transcripts = ASRNodeEngineStream(__scope, { __engine }) {
        it.transcripts
    }
    val partials = ASRNodeEngineStream(__scope, { __engine }) {
        it.partial_transcripts
    }
    val vad_probabilities =
        ASRNodeEngineStream(__scope, { __engine }) {
            it.vad_probabilities
        }
    val events = ASRNodeEngineStream(__scope, { __engine }) { engine ->
        engine.events.map {
            mapOf(
                "kind" to it.kind.raw,
                "data" to ASRJson.codec_safe(it.data),
            )
        }
    }

    private val __streams = listOf(
        turns, transcripts, partials, vad_probabilities, events,
    )

    val is_running: Boolean get() = __engine != null

    // ------------------------------------------------------------------
    // Public Methods
    // ------------------------------------------------------------------
    /**
     * Stops a running engine, then builds and starts one from [dict].
     * A failed start leaves nothing attached, exactly as before it.
     */
    suspend fun start(
        dict: Map<String, Any?>,
        on_load_progress: LoadProgressHandler? = null,
    ) = __lock.withLock {
        __stop_locked()
        val engine = ASREngine(config(dict, on_load_progress))
        __engine = engine
        for (s in __streams) s.bind(engine)
        try {
            engine.start()
        } catch (e: Throwable) {
            for (s in __streams) s.unbind()
            __engine = null
            throw e
        }
    }

    /** Stops capture and releases the models [start] loaded. */
    suspend fun stop() = __lock.withLock { __stop_locked() }

    // ------------------------------------------------------------------
    // Private Methods
    // ------------------------------------------------------------------
    private suspend fun __stop_locked() {
        for (s in __streams) s.unbind()
        val engine = __engine
        __engine = null
        engine?.stop()
    }

    companion object {
        const val DEFAULT_VAD = "TheStageAI/silero-vad"
        const val DEFAULT_STT = "TheStageAI/thewhisper-large-v3-turbo"

        /**
         * The Dart config map as a [TheStageAgentConfig]. Every key is
         * optional; an absent key keeps the SDK's tuned policy:
         * `vad`, `stt`, `vad_device`, `stt_device`, `stt_revision`,
         * `language`, `turn_silence_timeout_ms`,
         * `turn_asr_silence_hangover_ms`, `speakers` (`true` or a
         * map, see [ASRJson.speaker_setup]).
         */
        fun config(
            dict: Map<String, Any?>,
            on_load_progress: LoadProgressHandler? = null,
        ): TheStageAgentConfig {
            fun str(key: String): String? =
                (dict[key] as? String)?.takeIf { it.isNotEmpty() }
            fun int(key: String): Int? = (dict[key] as? Number)?.toInt()

            var turn: TurnConfig? = null
            int("turn_silence_timeout_ms")?.let {
                turn = (turn ?: TurnConfig()).copy(silence_timeout_ms = it)
            }
            int("turn_asr_silence_hangover_ms")?.let {
                turn = (turn ?: TurnConfig())
                    .copy(asr_silence_hangover_ms = it)
            }
            val base = TheStageAgentConfig(
                vad = str("vad") ?: DEFAULT_VAD,
                stt = str("stt") ?: DEFAULT_STT,
            )
            return base.copy(
                vad_device = str("vad_device") ?: base.vad_device,
                stt_device = str("stt_device") ?: base.stt_device,
                stt_revision = str("stt_revision") ?: base.stt_revision,
                stt_language = str("language") ?: base.stt_language,
                turn_config = turn,
                on_load_progress = on_load_progress,
                speaker_setup = ASRJson.speaker_setup(dict["speakers"]),
            )
        }
    }
}

// ----------------------------------------------------------------------
// TheStageFlutterPlugin + ASR node engine
// ----------------------------------------------------------------------
@Suppress("UNCHECKED_CAST")
internal fun TheStageFlutterPlugin.__handle_asr_engine_start(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val engine = __asr_node_engine
    if (engine == null) {
        result.success(null)
        return
    }
    val dict = (call.arguments as? Map<String, Any?>) ?: emptyMap()
    val on_load_progress: LoadProgressHandler? =
        __progress_sink?.let { sink ->
            { event: LoadProgress ->
                __scope.launch {
                    sink.success(__load_progress_event(event.model, event))
                }
            }
        }
    __scope.launch(Dispatchers.Default) {
        try {
            engine.start(dict, on_load_progress)
            withContext(Dispatchers.Main) { result.success(null) }
        } catch (e: Throwable) {
            withContext(Dispatchers.Main) {
                result.error(
                    "THESTAGE_ASR_ENGINE_ERROR",
                    e.message ?: e::class.simpleName,
                    null,
                )
            }
        }
    }
}

internal fun TheStageFlutterPlugin.__handle_asr_engine_stop(
    @Suppress("UNUSED_PARAMETER") call: MethodCall,
    result: MethodChannel.Result,
) {
    val engine = __asr_node_engine
    if (engine == null) {
        result.success(null)
        return
    }
    __scope.launch(Dispatchers.Default) {
        try {
            engine.stop()
        } catch (_: Throwable) {
        }
        withContext(Dispatchers.Main) { result.success(null) }
    }
}

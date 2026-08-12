package ai.thestage.qlip.tts_front_stream

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Debug
import android.os.Handler
import android.os.HandlerThread
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// ----------------------------------------------------------------------
// MainActivity
// ----------------------------------------------------------------------
/**
 * Streaming PCM playback bridge for the tts_stream
 * demo. Mirrors the iOS native_bridge protocol used
 * by `examples/tts_stream` in TheStageAI.AppleSDK so
 * the Flutter Dart code in `lib/main.dart` is
 * platform-agnostic:
 *
 *  - `startStream(int sampleRate)` — open an
 *    AudioTrack in MODE_STREAM (analogue of iOS
 *    AVAudioEngine + AVAudioPlayerNode).
 *  - `appendChunk(Float64List)` — push float64 PCM
 *    samples to the track. We convert to 16-bit
 *    int PCM here so we don't depend on API 21+
 *    float-PCM AudioTrack support.
 *  - `stopStream()` — drain and release the track.
 *  - `memory()` — heap + native heap sizes for the
 *    on-screen memory panel.
 */
class MainActivity : FlutterActivity() {

    // @Volatile because AudioTrack lifecycle and writes
    // run on a dedicated HandlerThread while stopStream
    // pauses/flushes the live track from the platform
    // thread to unblock an in-flight write() fast.
    @Volatile private var __track: AudioTrack? = null
    @Volatile private var __sample_rate: Int = 24000
    @Volatile private var __stop_requested: Boolean = false
    /** True while the current TTS session is being
     *  silenced because the device is in
     *  RINGER_MODE_SILENT. Vibrate mode keeps playing
     *  per Android convention. */
    @Volatile private var __suppress_playback: Boolean = false
    private var __audio_thread: HandlerThread? = null
    private var __audio_handler: Handler? = null

    companion object {
        private const val CHANNEL = "native_bridge"
        private const val TAG = "TtsStreamMain"
    }

    override fun configureFlutterEngine(
        engine: FlutterEngine
    ) {
        super.configureFlutterEngine(engine)

        __ensure_audio_thread()

        MethodChannel(
            engine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startStream" -> {
                    val sr = (call.arguments as? Number)
                        ?.toInt() ?: 24000
                    __post_audio { __start_stream(sr) }
                    result.success(null)
                }
                "appendChunk" -> {
                    val raw = call.arguments
                    val samples =
                        __extract_doubles(raw)
                    if (samples != null) {
                        __post_audio {
                            __append_chunk(samples)
                        }
                    }
                    result.success(null)
                }
                "stopStream" -> {
                    // Synchronous fast-path: signal stop
                    // and unblock the in-flight write()
                    // so the audio thread can drop the
                    // queue and tear down. Without this
                    // the queued __stop_stream sits
                    // behind seconds of buffered audio.
                    __stop_requested = true
                    val track = __track
                    if (track != null) {
                        try {
                            track.pause()
                        } catch (_: Throwable) {}
                        try {
                            track.flush()
                        } catch (_: Throwable) {}
                    }
                    __audio_handler
                        ?.removeCallbacksAndMessages(null)
                    __post_audio { __stop_stream() }
                    result.success(null)
                }
                "memory" -> {
                    result.success(__memory())
                }
                else -> result.notImplemented()
            }
        }
    }

    // ------------------------------------------------------------------
    // Audio worker thread
    // ------------------------------------------------------------------

    private fun __ensure_audio_thread() {
        if (__audio_thread == null) {
            __audio_thread = HandlerThread(
                "tts-stream-audio"
            ).apply { start() }
            __audio_handler =
                Handler(__audio_thread!!.looper)
        }
    }

    private fun __post_audio(task: () -> Unit) {
        __ensure_audio_thread()
        __audio_handler?.post(task)
    }

    // Public methods of MainActivity called via the
    // method-channel handler above. Names follow the
    // project's __double_underscore private prefix.
    private fun __start_stream(sample_rate: Int) {
        __stop_stream()
        // __stop_stream above sets __stop_requested = true;
        // clear it so the first __append_chunk for the
        // new session isn't skipped.
        __stop_requested = false
        __sample_rate = sample_rate
        __suppress_playback = __is_silent_ringer()
        if (__suppress_playback) return
        val min_buf = AudioTrack.getMinBufferSize(
            sample_rate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        // 4 s of headroom. AudioTrack's userspace write()
        // unblocks at the half-full watermark, so each
        // back-pressure block lasts ~2 s here. Bumped
        // from 2 s after the streaming-perf work shipped
        // — sentence-boundary stalls (worst observed
        // ~810 ms) used to flirt with the 1 s
        // half-buffer threshold; doubling moves the
        // safety margin from 1.2 s to 3.2 s and prevents
        // any underrun on slower devices.
        val seconds_of_buffer = 4
        val buf_size = maxOf(
            min_buf * 4,
            sample_rate * seconds_of_buffer * 2,
        )
        try {
            __track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(
                            AudioAttributes.USAGE_MEDIA
                        )
                        .setContentType(
                            AudioAttributes
                                .CONTENT_TYPE_SPEECH
                        )
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(
                            AudioFormat
                                .ENCODING_PCM_16BIT
                        )
                        .setSampleRate(sample_rate)
                        .setChannelMask(
                            AudioFormat
                                .CHANNEL_OUT_MONO
                        )
                        .build()
                )
                .setBufferSizeInBytes(buf_size)
                .setTransferMode(
                    AudioTrack.MODE_STREAM
                )
                .build()
                .apply {
                    // MODE_STREAM's default start
                    // threshold is the full buffer
                    // size — with a 4 s buffer the
                    // HAL won't begin output until
                    // 4 s of audio is queued, which
                    // delays first-audible-audio by
                    // seconds even though chunk #0
                    // arrived in ~1 s. Lower it so
                    // playback starts as soon as a
                    // single mixer tick worth of data
                    // is in the buffer.
                    if (android.os.Build.VERSION
                            .SDK_INT >= android.os
                            .Build.VERSION_CODES.S) {
                        try {
                            setStartThresholdInFrames(
                                1
                            )
                        } catch (_: Throwable) {}
                    }
                    play()
                }
        } catch (e: Exception) {
            android.util.Log.e(
                TAG,
                "AudioTrack start failed: " +
                    "${e.message}",
                e,
            )
            __track = null
        }
    }

    private fun __append_chunk(samples: DoubleArray) {
        if (__stop_requested) return
        val track = __track ?: return
        if (samples.isEmpty()) return
        // No software gain — USAGE_MEDIA routes to the
        // loudspeaker by default and is already loud enough. A 2×
        // boost would push speech peaks (~0.3-0.5) into
        // saturation on louder syllables.
        val pcm = ShortArray(samples.size) { i ->
            val v = samples[i]
            val clipped = when {
                v >= 1.0 -> 32767
                v <= -1.0 -> -32768
                else -> (v * 32767.0).toInt()
            }
            clipped.toShort()
        }
        try {
            track.write(pcm, 0, pcm.size)
        } catch (e: Exception) {
            android.util.Log.e(
                TAG,
                "AudioTrack write failed: " +
                    "${e.message}",
                e,
            )
        }
    }

    private fun __stop_stream() {
        __stop_requested = true
        try {
            __track?.let {
                try {
                    it.stop()
                } catch (_: IllegalStateException) {}
                it.release()
            }
        } catch (_: Exception) {}
        __track = null
        __suppress_playback = false
    }

    /** True when the device ringer is in SILENT mode.
     *  Used to honor the system silence preference for
     *  streaming TTS output. Vibrate mode keeps
     *  playing — only ringer/notification channels are
     *  silenced in vibrate per Android convention. */
    private fun __is_silent_ringer(): Boolean {
        val am = getSystemService(
            Context.AUDIO_SERVICE
        ) as? AudioManager ?: return false
        return am.ringerMode ==
            AudioManager.RINGER_MODE_SILENT
    }

    /** Tolerate either Float64List (Android plugin
     * change) or List<double> (legacy) coming from
     * Dart so the demo keeps working across plugin
     * versions. */
    private fun __extract_doubles(
        raw: Any?
    ): DoubleArray? {
        return when (raw) {
            is DoubleArray -> raw
            is FloatArray -> DoubleArray(raw.size) {
                raw[it].toDouble()
            }
            is List<*> -> DoubleArray(raw.size) { i ->
                (raw[i] as? Number)?.toDouble() ?: 0.0
            }
            else -> null
        }
    }

    private fun __memory(): Map<String, Double> {
        val runtime = Runtime.getRuntime()
        val heap_mb =
            (runtime.totalMemory() -
                runtime.freeMemory()) /
                (1024.0 * 1024.0)
        val native_mb =
            Debug.getNativeHeapAllocatedSize() /
                (1024.0 * 1024.0)
        return mapOf(
            "heap_mb" to heap_mb,
            "native_mb" to native_mb,
            // iOS-equivalent keys so the Apple-style
            // Dart code that reads `resident_mb` /
            // `footprint_mb` shows non-null values.
            "resident_mb" to native_mb,
            "footprint_mb" to heap_mb,
        )
    }

    override fun onDestroy() {
        __stop_requested = true
        val track = __track
        if (track != null) {
            try { track.pause() } catch (_: Throwable) {}
            try { track.flush() } catch (_: Throwable) {}
        }
        __audio_handler?.removeCallbacksAndMessages(null)
        __post_audio { __stop_stream() }
        __audio_thread?.quitSafely()
        __audio_thread = null
        __audio_handler = null
        super.onDestroy()
    }
}

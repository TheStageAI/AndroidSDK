package ai.thestage.thestage_android_sdk.streams

import ai.thestage.qlip.audio.DemoAudioCapture
import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.provider.MediaStore
import android.util.DisplayMetrics
import android.util.Log
import android.view.Surface
import java.io.File

// ----------------------------------------------------------------------
// ScreenDemoRecorder
// ----------------------------------------------------------------------
/**
 * Native screen-demo recorder: MediaProjection video + a clean stereo
 * audio track (mic = Left, assistant/TTS = Right) sourced from the SDK
 * [DemoAudioCapture] tee, muxed to an `.mp4` published to the gallery
 * (`Movies/`).
 *
 * Demo quality: robustness (no crashes / deadlocks) is prioritized over
 * sample-perfect A/V sync. All heavy work runs off the main thread; the
 * caller's completion callback is always delivered on the main thread.
 */
object ScreenDemoRecorder {

    // Public Attributes
    // ------------------------------------------------------------------
    @Volatile
    var recording: Boolean = false
        private set

    // Private Attributes
    // ------------------------------------------------------------------
    private const val TAG = "ScreenDemoRecorder"
    const val REQUEST_CODE = 0x5EC1

    private const val OUT_SAMPLE_RATE = 48000
    private const val AUDIO_CHANNELS = 2
    private const val MIX_TICK_MS = 20L
    // 20 ms @ 48 kHz.
    private const val MIX_FRAMES_PER_TICK = OUT_SAMPLE_RATE * 20 / 1000
    private const val MAX_LONG_SIDE = 1280
    private const val CODEC_TIMEOUT_US = 10_000L

    private val __main = Handler(Looper.getMainLooper())

    // Consent handshake state (main thread only).
    private var __app_context: Context? = null
    private var __pending_start: ((kotlin.Result<Unit>) -> Unit)? = null

    // Capture session (created on start, torn down on stop).
    private var __projection: MediaProjection? = null
    private var __projection_cb: MediaProjection.Callback? = null
    private var __virtual_display: VirtualDisplay? = null

    private var __video_codec: MediaCodec? = null
    private var __input_surface: Surface? = null
    private var __audio_codec: MediaCodec? = null
    private var __muxer: MediaMuxer? = null

    private var __out_file: File? = null

    private val __mux_lock = Any()
    private var __muxer_started = false
    private var __video_track = -1
    private var __audio_track = -1

    @Volatile
    private var __running = false
    @Volatile
    private var __stopping = false

    private var __video_drain: Thread? = null
    private var __audio_drain: Thread? = null

    private var __mix_thread: HandlerThread? = null
    private var __mix_handler: Handler? = null

    // Resampled-to-48 kHz PCM rings (drop-oldest on overflow).
    private val __mic_ring = PcmRing(OUT_SAMPLE_RATE * 2)
    private val __tts_ring = PcmRing(OUT_SAMPLE_RATE * 2)

    private var __audio_frames_written = 0L

    // Surface-input video PTS are absolute (SystemClock, µs). Rebase the
    // first frame to 0 so the muxed video shares the audio's 0-origin —
    // otherwise the two tracks sit on wildly different clocks and the
    // container duration blows up.
    private var __video_pts_base = -1L
    @Volatile
    private var __audio_eos_sent = false

    // Public Methods
    // ------------------------------------------------------------------
    /**
     * Begin recording. Triggers the system screen-capture consent
     * dialog via [activity]; [on_result] is delivered on the main
     * thread once capture is running (or on failure).
     */
    fun start(
        activity: Activity,
        on_result: (kotlin.Result<Unit>) -> Unit,
    ) {
        __main.post {
            if (recording || __pending_start != null) {
                on_result(
                    kotlin.Result.failure(
                        IllegalStateException(
                            "A recording is already in progress."
                        )
                    )
                )
                return@post
            }
            __app_context = activity.applicationContext
            __pending_start = on_result
            try {
                val mgr = activity.getSystemService(
                    Context.MEDIA_PROJECTION_SERVICE
                ) as MediaProjectionManager
                val intent = mgr.createScreenCaptureIntent()
                activity.startActivityForResult(intent, REQUEST_CODE)
            } catch (e: Throwable) {
                __pending_start = null
                on_result(
                    kotlin.Result.failure(
                        RuntimeException(
                            "Could not launch capture consent: " +
                                (e.message ?: e.toString())
                        )
                    )
                )
            }
        }
    }

    /**
     * Consent-dialog result relay. Returns true if [requestCode] was
     * ours (consumed), false otherwise.
     */
    fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: android.content.Intent?,
    ): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val cb = __pending_start
        __pending_start = null
        if (cb == null) return true

        if (resultCode != Activity.RESULT_OK || data == null) {
            cb(
                kotlin.Result.failure(
                    RuntimeException(
                        "Screen-capture permission was denied."
                    )
                )
            )
            return true
        }

        // Start the FGS first (Android 14+ ordering), then acquire the
        // projection once it is foregrounded.
        val ctx = __app_context
        if (ctx == null) {
            cb(
                kotlin.Result.failure(
                    RuntimeException("No application context.")
                )
            )
            return true
        }

        ScreenRecorderService.on_foreground = {
            ScreenRecorderService.on_foreground = null
            Thread {
                try {
                    __begin_capture(ctx, resultCode, data)
                    __main.post { cb(kotlin.Result.success(Unit)) }
                } catch (e: Throwable) {
                    Log.e(TAG, "begin_capture failed", e)
                    __teardown(publish = false)
                    __main.post {
                        cb(
                            kotlin.Result.failure(
                                RuntimeException(
                                    "Failed to start capture: " +
                                        (e.message ?: e.toString())
                                )
                            )
                        )
                    }
                }
            }.start()
        }
        ScreenRecorderService.start(ctx)
        return true
    }

    /**
     * Stop recording, finalize the file, and publish it to the
     * gallery. [on_result] is delivered on the main thread.
     */
    fun stop(on_result: (kotlin.Result<Unit>) -> Unit) {
        Thread {
            val uri: Uri? = try {
                if (!recording) null else __teardown(publish = true)
            } catch (e: Throwable) {
                Log.e(TAG, "stop/teardown failed", e)
                null
            }
            __main.post {
                if (uri != null || !__had_error) {
                    on_result(kotlin.Result.success(Unit))
                } else {
                    on_result(
                        kotlin.Result.failure(
                            RuntimeException(
                                "Recording stopped but the file " +
                                    "could not be saved."
                            )
                        )
                    )
                }
            }
        }.start()
    }

    // Private Methods
    // ------------------------------------------------------------------
    @Volatile
    private var __had_error = false

    private fun __begin_capture(
        ctx: Context,
        resultCode: Int,
        data: android.content.Intent,
    ) {
        __had_error = false
        __muxer_started = false
        __video_track = -1
        __audio_track = -1
        __audio_frames_written = 0L
        __video_pts_base = -1L
        __audio_eos_sent = false
        __stopping = false
        __mic_ring.clear()
        __tts_ring.clear()

        val mgr = ctx.getSystemService(
            Context.MEDIA_PROJECTION_SERVICE
        ) as MediaProjectionManager
        val projection = mgr.getMediaProjection(resultCode, data)
            ?: throw IllegalStateException(
                "getMediaProjection returned null."
            )
        __projection = projection

        val cb = object : MediaProjection.Callback() {
            override fun onStop() {
                // System / user revoked the projection.
                if (recording) {
                    stop {}
                }
            }
        }
        __projection_cb = cb
        // Callback registration is required on Android 14+.
        projection.registerCallback(cb, __main)

        // --- Output file --------------------------------------------
        val name = "thestage_demo_${System.currentTimeMillis()}.mp4"
        val file = File(ctx.cacheDir, name)
        __out_file = file

        // --- Display geometry ---------------------------------------
        val dm: DisplayMetrics = ctx.resources.displayMetrics
        var w = dm.widthPixels
        var h = dm.heightPixels
        val density = if (dm.densityDpi > 0) dm.densityDpi else 320
        val longest = maxOf(w, h)
        if (longest > MAX_LONG_SIDE) {
            val scale = MAX_LONG_SIDE.toDouble() / longest
            w = (w * scale).toInt()
            h = (h * scale).toInt()
        }
        // Encoders want even dimensions.
        w = w and 1.inv()
        h = h and 1.inv()
        if (w < 2) w = 2
        if (h < 2) h = 2

        // --- Video encoder ------------------------------------------
        val vfmt = MediaFormat.createVideoFormat(
            MediaFormat.MIMETYPE_VIDEO_AVC, w, h
        )
        vfmt.setInteger(
            MediaFormat.KEY_COLOR_FORMAT,
            MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface,
        )
        vfmt.setInteger(MediaFormat.KEY_BIT_RATE, 6_000_000)
        vfmt.setInteger(MediaFormat.KEY_FRAME_RATE, 30)
        vfmt.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        val vcodec = MediaCodec.createEncoderByType(
            MediaFormat.MIMETYPE_VIDEO_AVC
        )
        vcodec.configure(
            vfmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE
        )
        val surface = vcodec.createInputSurface()
        vcodec.start()
        __video_codec = vcodec
        __input_surface = surface

        // --- Virtual display ----------------------------------------
        __virtual_display = projection.createVirtualDisplay(
            "thestage-demo",
            w, h, density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            surface,
            null,
            __main,
        )

        // --- Audio encoder ------------------------------------------
        val afmt = MediaFormat.createAudioFormat(
            MediaFormat.MIMETYPE_AUDIO_AAC,
            OUT_SAMPLE_RATE,
            AUDIO_CHANNELS,
        )
        afmt.setInteger(
            MediaFormat.KEY_AAC_PROFILE,
            MediaCodecInfo.CodecProfileLevel.AACObjectLC,
        )
        afmt.setInteger(MediaFormat.KEY_BIT_RATE, 128_000)
        afmt.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16_384)
        val acodec = MediaCodec.createEncoderByType(
            MediaFormat.MIMETYPE_AUDIO_AAC
        )
        acodec.configure(
            afmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE
        )
        acodec.start()
        __audio_codec = acodec

        // --- Muxer --------------------------------------------------
        __muxer = MediaMuxer(
            file.absolutePath,
            MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4,
        )

        __running = true
        recording = true

        // --- Audio tee ----------------------------------------------
        DemoAudioCapture.on_mic = { samples, rate ->
            try {
                __mic_ring.write(__resample(samples, rate))
            } catch (_: Throwable) {}
        }
        DemoAudioCapture.on_playback = { samples, rate ->
            try {
                __tts_ring.write(__resample(samples, rate))
            } catch (_: Throwable) {}
        }
        DemoAudioCapture.enabled = true

        // --- Drain + mix threads ------------------------------------
        __video_drain = Thread({ __drain_video() }, "sr-video").also {
            it.start()
        }
        __audio_drain = Thread({ __drain_audio() }, "sr-audio").also {
            it.start()
        }
        val mt = HandlerThread("sr-mix").also { it.start() }
        __mix_thread = mt
        val mh = Handler(mt.looper)
        __mix_handler = mh
        mh.post(object : Runnable {
            override fun run() {
                if (!__running && __audio_eos_sent) return
                try {
                    __mix_tick()
                } catch (e: Throwable) {
                    Log.w(TAG, "mix tick: ${e.message}")
                }
                mh.postDelayed(this, MIX_TICK_MS)
            }
        })
    }

    /** Linear resample [samples] from [rate] Hz to 48 kHz mono. */
    private fun __resample(samples: FloatArray, rate: Int): FloatArray {
        if (samples.isEmpty()) return samples
        if (rate == OUT_SAMPLE_RATE) return samples.copyOf()
        val out_len = ((samples.size.toLong() * OUT_SAMPLE_RATE) /
            rate).toInt().coerceAtLeast(1)
        val out = FloatArray(out_len)
        val step = rate.toDouble() / OUT_SAMPLE_RATE
        var pos = 0.0
        for (i in 0 until out_len) {
            val i0 = pos.toInt()
            val frac = pos - i0
            val a = samples[i0.coerceIn(0, samples.size - 1)]
            val b = samples[(i0 + 1).coerceIn(0, samples.size - 1)]
            out[i] = (a + (b - a) * frac).toFloat()
            pos += step
        }
        return out
    }

    /** Pull one 20 ms chunk, mix L=mic/R=tts, feed the AAC encoder. */
    private fun __mix_tick() {
        val codec = __audio_codec ?: return

        if (__stopping && !__audio_eos_sent) {
            val idx = codec.dequeueInputBuffer(0)
            if (idx >= 0) {
                codec.queueInputBuffer(
                    idx, 0, 0,
                    __audio_pts_us(),
                    MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                )
                __audio_eos_sent = true
            }
            return
        }
        if (__stopping) return

        val n = MIX_FRAMES_PER_TICK
        val mic = FloatArray(n)
        val tts = FloatArray(n)
        __mic_ring.read(mic, n)
        __tts_ring.read(tts, n)

        val idx = codec.dequeueInputBuffer(0)
        if (idx < 0) return  // encoder busy — skip; PTS stays consistent
        val buf = codec.getInputBuffer(idx) ?: return
        buf.clear()
        for (i in 0 until n) {
            buf.putShort(__to_pcm16(mic[i]))
            buf.putShort(__to_pcm16(tts[i]))
        }
        val bytes = n * AUDIO_CHANNELS * 2
        codec.queueInputBuffer(idx, 0, bytes, __audio_pts_us(), 0)
        __audio_frames_written += n
    }

    private fun __audio_pts_us(): Long =
        __audio_frames_written * 1_000_000L / OUT_SAMPLE_RATE

    private fun __to_pcm16(v: Float): Short {
        val c = when {
            v > 1f -> 1f
            v < -1f -> -1f
            else -> v
        }
        return (c * 32767f).toInt().toShort()
    }

    private fun __maybe_start_muxer() {
        // Caller holds __mux_lock.
        if (__muxer_started) return
        if (__video_track >= 0 && __audio_track >= 0) {
            __muxer?.start()
            __muxer_started = true
        }
    }

    private fun __drain_video() {
        val codec = __video_codec ?: return
        val info = MediaCodec.BufferInfo()
        var idle = 0
        while (true) {
            val idx = try {
                codec.dequeueOutputBuffer(info, CODEC_TIMEOUT_US)
            } catch (e: Throwable) {
                Log.w(TAG, "video dequeue: ${e.message}")
                break
            }
            when {
                idx == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (__stopping && ++idle > 300) break
                }
                idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    synchronized(__mux_lock) {
                        if (__video_track < 0) {
                            __video_track =
                                __muxer!!.addTrack(codec.outputFormat)
                            __maybe_start_muxer()
                        }
                    }
                }
                idx >= 0 -> {
                    idle = 0
                    val buf = codec.getOutputBuffer(idx)
                    if (info.flags and
                        MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                    ) {
                        info.size = 0
                    }
                    if (info.size > 0 && buf != null) {
                        __await_muxer()
                        if (__muxer_started) {
                            if (__video_pts_base < 0) {
                                __video_pts_base = info.presentationTimeUs
                            }
                            info.presentationTimeUs =
                                info.presentationTimeUs - __video_pts_base
                            buf.position(info.offset)
                            buf.limit(info.offset + info.size)
                            synchronized(__mux_lock) {
                                __muxer?.writeSampleData(
                                    __video_track, buf, info
                                )
                            }
                        }
                    }
                    try {
                        codec.releaseOutputBuffer(idx, false)
                    } catch (_: Throwable) {}
                    if (info.flags and
                        MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    ) {
                        break
                    }
                }
            }
        }
    }

    private fun __drain_audio() {
        val codec = __audio_codec ?: return
        val info = MediaCodec.BufferInfo()
        var idle = 0
        while (true) {
            val idx = try {
                codec.dequeueOutputBuffer(info, CODEC_TIMEOUT_US)
            } catch (e: Throwable) {
                Log.w(TAG, "audio dequeue: ${e.message}")
                break
            }
            when {
                idx == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (__stopping && ++idle > 300) break
                }
                idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    synchronized(__mux_lock) {
                        if (__audio_track < 0) {
                            __audio_track =
                                __muxer!!.addTrack(codec.outputFormat)
                            __maybe_start_muxer()
                        }
                    }
                }
                idx >= 0 -> {
                    idle = 0
                    val buf = codec.getOutputBuffer(idx)
                    if (info.flags and
                        MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                    ) {
                        info.size = 0
                    }
                    if (info.size > 0 && buf != null) {
                        __await_muxer()
                        if (__muxer_started) {
                            buf.position(info.offset)
                            buf.limit(info.offset + info.size)
                            synchronized(__mux_lock) {
                                __muxer?.writeSampleData(
                                    __audio_track, buf, info
                                )
                            }
                        }
                    }
                    try {
                        codec.releaseOutputBuffer(idx, false)
                    } catch (_: Throwable) {}
                    if (info.flags and
                        MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    ) {
                        break
                    }
                }
            }
        }
    }

    /** Spin briefly until both tracks are added and the muxer starts. */
    private fun __await_muxer() {
        var spins = 0
        while (!__muxer_started && __running && spins < 2000) {
            try {
                Thread.sleep(1)
            } catch (_: InterruptedException) {
                break
            }
            spins++
        }
    }

    /**
     * Tear down the whole session best-effort. When [publish] is true,
     * the finalized file is copied into `MediaStore` (Movies/).
     * Returns the published [Uri] or null. Safe to call once per
     * session; sets [recording] false.
     */
    private fun __teardown(publish: Boolean): Uri? {
        recording = false
        __running = false
        __stopping = true

        // Stop mirroring first so the video encoder can drain to EOS.
        try {
            __virtual_display?.release()
        } catch (e: Throwable) {
            Log.w(TAG, "vd release: ${e.message}")
        }
        __virtual_display = null

        // Signal EOS to the video encoder (surface input).
        try {
            __video_codec?.signalEndOfInputStream()
        } catch (e: Throwable) {
            Log.w(TAG, "video EOS: ${e.message}")
        }

        // Let the mix loop queue the audio EOS, then wait for it.
        val eos_deadline = System.currentTimeMillis() + 1500
        while (!__audio_eos_sent &&
            System.currentTimeMillis() < eos_deadline
        ) {
            try {
                Thread.sleep(5)
            } catch (_: InterruptedException) {
                break
            }
        }

        // Wait for both drain loops to flush EOS.
        try {
            __video_drain?.join(3000)
        } catch (_: InterruptedException) {}
        try {
            __audio_drain?.join(3000)
        } catch (_: InterruptedException) {}
        __video_drain = null
        __audio_drain = null

        // Stop the mixer clock.
        try {
            __mix_thread?.quitSafely()
        } catch (e: Throwable) {
            Log.w(TAG, "mix quit: ${e.message}")
        }
        __mix_handler = null
        __mix_thread = null

        // Detach the audio tee.
        DemoAudioCapture.enabled = false
        DemoAudioCapture.on_mic = null
        DemoAudioCapture.on_playback = null

        // Finalize the muxer.
        val was_started = __muxer_started
        synchronized(__mux_lock) {
            try {
                if (was_started) __muxer?.stop()
            } catch (e: Throwable) {
                Log.w(TAG, "muxer stop: ${e.message}")
                __had_error = true
            }
            try {
                __muxer?.release()
            } catch (e: Throwable) {
                Log.w(TAG, "muxer release: ${e.message}")
            }
        }
        __muxer = null
        __muxer_started = false

        // Release encoders.
        try {
            __video_codec?.stop()
        } catch (_: Throwable) {}
        try {
            __video_codec?.release()
        } catch (_: Throwable) {}
        __video_codec = null
        try {
            __input_surface?.release()
        } catch (_: Throwable) {}
        __input_surface = null
        try {
            __audio_codec?.stop()
        } catch (_: Throwable) {}
        try {
            __audio_codec?.release()
        } catch (_: Throwable) {}
        __audio_codec = null

        // Release the projection.
        try {
            __projection_cb?.let { __projection?.unregisterCallback(it) }
        } catch (_: Throwable) {}
        __projection_cb = null
        try {
            __projection?.stop()
        } catch (_: Throwable) {}
        __projection = null

        // Stop the foreground service.
        val ctx = __app_context
        ScreenRecorderService.on_foreground = null
        if (ctx != null) ScreenRecorderService.stop(ctx)

        // Publish to the gallery.
        var uri: Uri? = null
        val file = __out_file
        if (publish && was_started && ctx != null && file != null &&
            file.exists() && file.length() > 0
        ) {
            uri = try {
                __publish_to_gallery(ctx, file)
            } catch (e: Throwable) {
                Log.e(TAG, "publish failed", e)
                __had_error = true
                null
            }
        } else if (publish && !was_started) {
            __had_error = true
        }
        // Remove the working copy regardless.
        try {
            file?.delete()
        } catch (_: Throwable) {}
        __out_file = null

        return uri
    }

    private fun __publish_to_gallery(ctx: Context, file: File): Uri {
        val resolver = ctx.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, file.name)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            values.put(
                MediaStore.Video.Media.RELATIVE_PATH,
                "Movies/TheStageDemos",
            )
            values.put(MediaStore.Video.Media.IS_PENDING, 1)
        }
        val collection =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Video.Media.getContentUri(
                    MediaStore.VOLUME_EXTERNAL_PRIMARY
                )
            } else {
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            }
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException(
                "MediaStore insert returned null."
            )
        resolver.openOutputStream(uri)?.use { out ->
            file.inputStream().use { it.copyTo(out) }
        } ?: throw IllegalStateException(
            "Could not open MediaStore output stream."
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            values.clear()
            values.put(MediaStore.Video.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        }
        return uri
    }

    // ------------------------------------------------------------------
    // PcmRing — fixed-capacity float ring, drop-oldest on overflow.
    // ------------------------------------------------------------------
    private class PcmRing(private val capacity: Int) {
        private val buf = FloatArray(capacity)
        private var head = 0   // read index
        private var count = 0

        @Synchronized
        fun clear() {
            head = 0
            count = 0
        }

        @Synchronized
        fun write(src: FloatArray) {
            for (v in src) {
                if (count == capacity) {
                    // Drop oldest so a stall can't grow unbounded.
                    head = (head + 1) % capacity
                    count--
                }
                buf[(head + count) % capacity] = v
                count++
            }
        }

        /** Fill [out] with up to [n] samples; zero-pad the remainder. */
        @Synchronized
        fun read(out: FloatArray, n: Int) {
            val take = if (n < count) n else count
            for (i in 0 until take) {
                out[i] = buf[(head + i) % capacity]
            }
            for (i in take until n) out[i] = 0f
            head = (head + take) % capacity
            count -= take
        }
    }
}

package ai.thestage.voice_agent

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity

// ----------------------------------------------------------------------
// MainActivity
// ----------------------------------------------------------------------
/**
 * voice_agent Android entry point.
 *
 * The TheStage SDK voice agent owns all audio (mic capture,
 * VAD, wake-word, ASR, LLM, TTS, AEC, barge-in, ducking)
 * natively, so this activity hosts no audio bridge — it is a
 * plain [FlutterActivity].
 *
 * It keeps two responsibilities:
 *   1. Request RECORD_AUDIO at launch. This example does not
 *      depend on the `record` plugin (the SDK owns audio), so
 *      the runtime permission is requested here directly.
 *   2. Start [AudioCaptureService], the microphone +
 *      mediaPlayback foreground service. Android 14+ requires
 *      such an FGS for the SDK's in-process AudioRecord
 *      (VOICE_COMMUNICATION) + AudioTrack duplex pipe to keep
 *      delivering samples while the activity is backgrounded.
 *      The OS rejects a microphone-type FGS unless RECORD_AUDIO
 *      is already granted, so the start is gated on the runtime
 *      permission and retried in [onResume] after the grant.
 */
class MainActivity : FlutterActivity() {

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------

    override fun onResume() {
        super.onResume()
        __ensure_record_permission()
        // Retry the FGS start after the user has had a chance to
        // grant RECORD_AUDIO. Idempotent.
        __start_foreground_service()
    }

    override fun onDestroy() {
        __stop_foreground_service()
        super.onDestroy()
    }

    // ------------------------------------------------------------------
    // Private Methods
    // ------------------------------------------------------------------

    /** Request RECORD_AUDIO if it has not been granted yet. */
    private fun __ensure_record_permission() {
        if (checkSelfPermission(
                Manifest.permission.RECORD_AUDIO,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.RECORD_AUDIO),
                REQ_RECORD_AUDIO,
            )
        }
    }

    /** Start the mic + playback foreground service. Idempotent;
     *  no-op until RECORD_AUDIO is granted. */
    private fun __start_foreground_service() {
        if (checkSelfPermission(
                Manifest.permission.RECORD_AUDIO,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        try {
            val intent = Intent(
                applicationContext,
                AudioCaptureService::class.java,
            )
            applicationContext.startForegroundService(intent)
        } catch (e: Exception) {
            android.util.Log.e(
                TAG,
                "startForegroundService failed: ${e.message}",
            )
        }
    }

    private fun __stop_foreground_service() {
        try {
            applicationContext.stopService(
                Intent(
                    applicationContext,
                    AudioCaptureService::class.java,
                ),
            )
        } catch (_: Exception) {}
    }

    companion object {
        private const val TAG = "VoiceAgentMain"
        private const val REQ_RECORD_AUDIO = 1001
    }
}

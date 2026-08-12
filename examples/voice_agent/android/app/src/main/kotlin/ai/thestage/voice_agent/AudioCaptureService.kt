package ai.thestage.voice_agent

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder

// ----------------------------------------------------------------------
// AudioCaptureService
// ----------------------------------------------------------------------
/**
 * Foreground service required by Android 14+ for
 * microphone access. Without this, Samsung devices
 * return silence or heavily attenuated audio.
 */
class AudioCaptureService : Service() {

    companion object {
        private const val CHANNEL_ID =
            "audio_capture"
        private const val NOTIFICATION_ID = 1
    }

    override fun onBind(intent: Intent?): IBinder? =
        null

    override fun onCreate() {
        super.onCreate()
        __create_notification_channel()
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int
    ): Int {
        val notification = Notification.Builder(
            this, CHANNEL_ID
        )
            .setContentTitle("Voice Agent")
            .setContentText("Listening...")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .build()

        try {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo
                    .FOREGROUND_SERVICE_TYPE_MICROPHONE or
                    ServiceInfo
                        .FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } catch (e: SecurityException) {
            // RECORD_AUDIO not granted yet — defer the
            // FGS start. MainActivity retries on the
            // next onResume after the permission flow.
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun __create_notification_channel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Audio Capture",
            NotificationManager.IMPORTANCE_LOW
        )
        channel.description =
            "Active during voice transcription"
        val manager = getSystemService(
            NotificationManager::class.java
        )
        manager.createNotificationChannel(channel)
    }
}

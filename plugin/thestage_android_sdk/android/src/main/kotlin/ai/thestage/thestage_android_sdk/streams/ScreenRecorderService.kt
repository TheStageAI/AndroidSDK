package ai.thestage.thestage_android_sdk.streams

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

// ----------------------------------------------------------------------
// ScreenRecorderService
// ----------------------------------------------------------------------
/**
 * Foreground service (type `mediaProjection`) that keeps the process
 * alive while [ScreenDemoRecorder] captures the screen.
 *
 * Android 14+ requires a `mediaProjection` foreground service to be
 * running *before* `MediaProjectionManager.getMediaProjection(...)` is
 * called. The recorder starts this service, waits for
 * [on_foreground] to fire (posted right after `startForeground`), then
 * acquires the projection.
 */
class ScreenRecorderService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        try {
            __start_foreground()
        } catch (e: Throwable) {
            Log.e(TAG, "startForeground failed: ${e.message}")
        }
        // Notify the recorder that the FGS is up so it can safely
        // acquire the MediaProjection (Android 14+ ordering).
        try {
            on_foreground?.invoke()
        } catch (e: Throwable) {
            Log.w(TAG, "on_foreground callback failed: ${e.message}")
        }
        return START_NOT_STICKY
    }

    // Private Methods
    // ------------------------------------------------------------------
    private fun __start_foreground() {
        val nm = getSystemService(
            Context.NOTIFICATION_SERVICE
        ) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val existing = nm.getNotificationChannel(CHANNEL_ID)
            if (existing == null) {
                val ch = NotificationChannel(
                    CHANNEL_ID,
                    "Screen recording",
                    NotificationManager.IMPORTANCE_LOW,
                )
                ch.description = "Demo screen capture is running."
                nm.createNotificationChannel(ch)
            }
        }

        val notif: Notification =
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("Recording demo")
                .setContentText("Screen + audio capture in progress.")
                .setSmallIcon(android.R.drawable.presence_video_online)
                .setOngoing(true)
                .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIF_ID,
                notif,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } else {
            startForeground(NOTIF_ID, notif)
        }
    }

    // Companion
    // ------------------------------------------------------------------
    companion object {
        private const val TAG = "ScreenRecorderService"
        private const val CHANNEL_ID = "thestage_screen_recorder"
        private const val NOTIF_ID = 0x5EC0

        /**
         * Fired on the main thread right after `startForeground`.
         * The recorder sets this before starting the service and
         * clears it once consumed.
         */
        @Volatile
        var on_foreground: (() -> Unit)? = null

        fun start(context: Context) {
            val intent = Intent(
                context, ScreenRecorderService::class.java
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            try {
                context.stopService(
                    Intent(
                        context,
                        ScreenRecorderService::class.java,
                    )
                )
            } catch (e: Throwable) {
                Log.w(TAG, "stopService failed: ${e.message}")
            }
        }
    }
}

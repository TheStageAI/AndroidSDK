package ai.thestage.thestage_android_sdk.streams

import ai.thestage.qlip.TheStageAI
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

// ----------------------------------------------------------------------
// DeveloperLogStream
// ----------------------------------------------------------------------
/**
 * Streams the SDK's diagnostics-ring lines to the Dart `logs`
 * EventChannel so a developer running `flutter run` sees the SDK's
 * lifecycle log, which otherwise lives only in `adb logcat`. Mirrors
 * the Apple SDK's `FlutterDeveloperLogSink` / `LogStreamHandler`.
 *
 * On listen it replays the current ring (so a late subscriber still
 * sees the session's history) then attaches a live listener via
 * [TheStageAI.set_log_listener]. Lines are already path-sanitized and
 * carry no user content (the record_log invariant). EventSink calls
 * are marshalled to the main thread as Flutter requires.
 */
class DeveloperLogStream : EventChannel.StreamHandler {

    // Private Attributes
    // ------------------------------------------------------------------
    private val __main = Handler(Looper.getMainLooper())

    // EventChannel.StreamHandler
    // ------------------------------------------------------------------
    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink?,
    ) {
        if (events == null) return
        // Replay the ring first (best-effort), then go live. A line
        // landing in the tiny gap between is at worst dropped from
        // `flutter run`; the ring + session file still hold it.
        val backlog = try {
            TheStageAI.recent_logs()
        } catch (_: Throwable) {
            emptyList()
        }
        __main.post {
            for (line in backlog) {
                try { events.success(line) } catch (_: Throwable) {}
            }
        }
        TheStageAI.set_log_listener { line ->
            __main.post {
                try { events.success(line) } catch (_: Throwable) {}
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        TheStageAI.set_log_listener(null)
    }
}

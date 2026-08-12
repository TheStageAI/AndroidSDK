package ai.thestage.thestage_android_sdk.handlers

import ai.thestage.thestage_android_sdk.TheStageFlutterPlugin
import ai.thestage.thestage_android_sdk.streams.ScreenDemoRecorder
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// ----------------------------------------------------------------------
// Screen Recorder Handlers
// ----------------------------------------------------------------------
//
// In-app screen capture (MediaProjection) that muxes app playback + mic
// into the recorded clip. Delegates to [ScreenDemoRecorder]; the plugin
// supplies the current Activity (needed for the capture-consent dialog)
// and relays the consent result via its ActivityResultListener.

internal fun TheStageFlutterPlugin.__handle_screen_recorder_is_recording(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    result.success(ScreenDemoRecorder.recording)
}

internal fun TheStageFlutterPlugin.__handle_screen_recorder_start(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val activity = __activity
    if (activity == null) {
        result.error(
            "screen_recorder_start",
            "No foreground Activity; cannot request screen capture.",
            null,
        )
        return
    }
    ScreenDemoRecorder.start(activity) { outcome ->
        outcome
            .onSuccess { result.success(null) }
            .onFailure { e ->
                result.error(
                    "screen_recorder_start",
                    e.message ?: "Failed to start screen recording.",
                    null,
                )
            }
    }
}

internal fun TheStageFlutterPlugin.__handle_screen_recorder_stop(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    ScreenDemoRecorder.stop { outcome ->
        outcome
            .onSuccess { result.success(null) }
            .onFailure { e ->
                result.error(
                    "screen_recorder_stop",
                    e.message ?: "Failed to stop screen recording.",
                    null,
                )
            }
    }
}

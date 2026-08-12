package ai.thestage.engine_bench

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// ----------------------------------------------------------------------
// MainActivity
// ----------------------------------------------------------------------
/**
 * Android host for EngineBench. Exposes a single "engine_bench"
 * MethodChannel with a `device_info` method so the Dart side can
 * stamp exported benchmark reports with the phone's hardware
 * identity (the value that actually matters when comparing tok/s
 * across a fleet). All model loading + inference happens inside the
 * thestage_android_sdk plugin.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "engine_bench"
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)

        MethodChannel(
            engine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "device_info" -> result.success(__device_info())
                else -> result.notImplemented()
            }
        }
    }

    // Hardware identity for the export envelope. Mirrors the Apple
    // SDK's `modelIdentifier` (e.g. "iPhone17,2") with the closest
    // Android equivalents.
    private fun __device_info(): Map<String, String> {
        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "device" to Build.DEVICE,
            "hardware" to Build.HARDWARE,
            "board" to Build.BOARD,
            "android_release" to Build.VERSION.RELEASE,
            "sdk_int" to Build.VERSION.SDK_INT.toString(),
        )
    }
}

package ai.thestage.thestage_android_sdk.handlers

import ai.thestage.qlip.TheStageAI
import ai.thestage.qlip.utils.LoadProgress
import ai.thestage.qlip.utils.LoadProgressHandler
import ai.thestage.thestage_android_sdk.EspeakPhonemizer
import ai.thestage.thestage_android_sdk.TheStageFlutterPlugin
import ai.thestage.thestage_android_sdk.internal.__encode_status
import ai.thestage.thestage_android_sdk.internal.__fail
import ai.thestage.thestage_android_sdk.internal.__load_progress_event
import ai.thestage.thestage_android_sdk.internal.__parse_devices
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// ----------------------------------------------------------------------
// Lifecycle Handlers
// ----------------------------------------------------------------------

@Suppress("UNCHECKED_CAST")
internal fun TheStageFlutterPlugin.__handle_initialize(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val args = call.arguments as? Map<String, Any?>
    val api_token = (args?.get("api_token") as? String)
        ?.takeIf { it.isNotEmpty() }

    // initialize is now suspend AND validates the token
    // during init (mirrors iOS initialize(apiToken:)), so a
    // bad token throws TokenValidationFailed. Run off-main
    // and surface the failure to Dart via result.error so
    // Dart's initialize() throws, matching iOS.
    __scope.launch(Dispatchers.Default) {
        try {
            // Register context-bound singletons with the SDK
            // BEFORE initialize(): token validation now runs
            // during init and its offline device-id path needs
            // the registered Context (else "Application context
            // not registered"). This also lets the SDK's
            // pipelines load without a Context later:
            //   * phonemizer provider "espeak_ng" — NeuTTS
            //     looks it up when phonemizer/metadata.json
            //     declares provider=espeak_ng.
            //   * APK native-lib dir — LLM pipelines read
            //     ADSP_LIBRARY_PATH / JNI libs from the SDK
            //     registry.
            //   * Context + PowerManager — for the download
            //     foreground service + wake lock.
            val ctx = __app_context
            if (ctx != null) {
                // espeak-ng is TTS-only. ASR-only apps can
                // ship without the native lib — loading
                // EspeakPhonemizer pulls in EspeakNg which
                // triggers System.loadLibrary("espeak_ng_jni");
                // swallow the UnsatisfiedLinkError so init
                // still succeeds and the SDK just doesn't
                // register a phonemizer.
                //
                // This registers the bundled espeak-ng under
                // the `espeak_ng` provider id — the default
                // backend the SDK falls back to when no host
                // has injected a factory via PhonemizerRegistry.
                // The host override is now consulted per model
                // load inside NeuTTS (nano path, language-
                // aware), matching iOS; the plugin's
                // PhonemizerRegistry forwards a host's factory
                // straight to the SDK registry.
                try {
                    TheStageAI.registerPhonemizer(
                        "espeak_ng",
                        EspeakPhonemizer(ctx, language = "en-us"),
                    )
                } catch (t: Throwable) {
                    Log.w(
                        TheStageFlutterPlugin.TAG,
                        "espeak_ng phonemizer unavailable " +
                            "(ASR-only build?): ${t.message}"
                    )
                }
                TheStageAI.registerNativeLibDir(
                    ctx.applicationInfo.nativeLibraryDir
                )
                TheStageAI.registerContext(ctx)
                (ctx.getSystemService(
                    android.content.Context.POWER_SERVICE
                ) as? android.os.PowerManager)?.let {
                    TheStageAI.registerPowerManager(it)
                }
            }

            // initialize validates the token during init (mirrors
            // iOS initialize(apiToken:)); a bad token throws
            // TokenValidationFailed, surfaced to Dart via
            // result.error so Dart's initialize() throws too.
            TheStageAI.initialize(api_token = api_token)

            withContext(Dispatchers.Main) {
                result.success(null)
            }
        } catch (e: Exception) {
            withContext(Dispatchers.Main) {
                __fail(result, e)
            }
        }
    }
}

@Suppress("UNCHECKED_CAST")
internal fun TheStageFlutterPlugin.__handle_start_model(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val args = call.arguments as? Map<String, Any>
    if (args == null) {
        __fail(result, "Missing arguments.")
        return
    }

    val model_name = args["model_name"] as? String
    val engines_path = args["engines_path"] as? String
    if (model_name == null || engines_path == null) {
        __fail(
            result,
            "Missing model_name or engines_path."
        )
        return
    }

    val model_type = args["model_type"] as? String
    val device = args["device"] as? String ?: "gpu"
    val devices = __parse_devices(args["devices"])
    val config = args["config"] as? Map<String, Any?>
    val revision = args["revision"] as? String ?: "main"

    // The progress EventChannel now emits the structured
    // LoadProgress (phase / fraction / model) map.
    val on_load_progress: LoadProgressHandler? =
        __progress_sink?.let { sink ->
            { event: LoadProgress ->
                __scope.launch {
                    sink.success(
                        __load_progress_event(model_name, event)
                    )
                }
            }
        }

    // Genie / large tokenizer / mmap must not run on main —
    // ANR otherwise. Wake lock + foreground service are
    // acquired by TheStageAI.start_model internally.
    __scope.launch(Dispatchers.Default) {
        try {
            val status = TheStageAI.start_model(
                model_name = model_name,
                engines_path = engines_path,
                model_type = model_type,
                revision = revision,
                device = device,
                devices = devices,
                config = config,
                on_load_progress = on_load_progress,
            )
            withContext(Dispatchers.Main) {
                result.success(__encode_status(status))
            }
        } catch (e: Exception) {
            withContext(Dispatchers.Main) {
                __fail(result, e)
            }
        }
    }
}

internal fun TheStageFlutterPlugin.__handle_stop_model(
    call: MethodCall,
    result: MethodChannel.Result,
) {
    val args = call.arguments as? Map<*, *>
    val model_name = args?.get("model_name") as? String
    if (model_name == null) {
        __fail(result, "Missing model_name.")
        return
    }
    try {
        val status = TheStageAI.stop_model(
            model_name = model_name
        )
        result.success(__encode_status(status))
    } catch (e: Exception) {
        __fail(result, e)
    }
}

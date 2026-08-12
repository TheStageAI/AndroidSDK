package ai.thestage.thestage_android_sdk

import ai.thestage.qlip.models.phonemizer.PhonemizerProvider
import ai.thestage.qlip.models.phonemizer.PhonemizerRegistry as SdkPhonemizerRegistry

// ----------------------------------------------------------------------
// PhonemizerRegistry (plugin forward)
// ----------------------------------------------------------------------
/**
 * Host-facing injection point for a [PhonemizerProvider] used
 * by phoneme-based nano TTS models (`neutts` / `neutts-nano` /
 * `neu-tts`).
 *
 * This is a thin forward to the SDK's
 * [ai.thestage.qlip.models.phonemizer.PhonemizerRegistry]. The
 * SDK consults the registry per model load, on the nano
 * resolution path, with the model's language (from the start
 * config, default `en-us`). A registered factory wins over the
 * bundle's declared phonemizer; multilingual models never
 * consult it.
 *
 * Register once, early (e.g. in `Application.onCreate`), before
 * loading a nano model:
 *
 *   PhonemizerRegistry.register { language ->
 *       MyPhonemizer(context, language)
 *   }
 *
 * The most recent registration wins; pass `null` to clear. If
 * no factory is registered, the bundled espeak-ng phonemizer
 * (registered by the plugin at `initialize`) is used.
 */
object PhonemizerRegistry {

    /**
     * Register a factory that builds a [PhonemizerProvider]
     * for a given language. Forwards to the SDK registry.
     * The most recent registration wins. Pass `null` to clear.
     */
    fun register(
        factory: ((language: String) -> PhonemizerProvider?)?
    ) {
        SdkPhonemizerRegistry.register(factory)
    }

    /** Whether an app has registered a phonemizer factory. */
    val isRegistered: Boolean
        get() = SdkPhonemizerRegistry.isRegistered
}

package ai.thestage.thestage_android_sdk

// ----------------------------------------------------------------------
// EspeakNg
// ----------------------------------------------------------------------
/**
 * JNI bridge to the native espeak-ng library.
 *
 * All native calls go through this object so the
 * companion [System.loadLibrary] call happens once.
 */
internal object EspeakNg {

    init {
        System.loadLibrary("espeak_ng_jni")
    }

    @JvmStatic
    external fun nativeInitialize(
        data_path: String,
        language: String
    ): Boolean

    @JvmStatic
    external fun nativeCompileData(
        data_root: String,
        phsource_path: String,
        dictsource_path: String
    ): Boolean

    @JvmStatic
    external fun nativeTextToPhonemes(
        text: String
    ): String

    @JvmStatic
    external fun nativeSetVoice(
        voice_name: String
    ): Boolean
}

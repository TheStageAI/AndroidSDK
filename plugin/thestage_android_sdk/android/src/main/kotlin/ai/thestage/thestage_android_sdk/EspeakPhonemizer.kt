package ai.thestage.thestage_android_sdk

import ai.thestage.qlip.models.phonemizer.PhonemizerProvider
import android.content.Context
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

// ----------------------------------------------------------------------
// EspeakPhonemizer
// ----------------------------------------------------------------------
/**
 * Phonemizer backed by the espeak-ng C library
 * (via JNI).
 *
 * Mirrors the iOS `EspeakPhonemizer`:
 *  - [preprocess] — language-specific text hook.
 *  - [clean] — language-specific phoneme hook.
 *  - [phonemize] — full pipeline: preprocess ->
 *      espeak -> clean.
 *
 * espeak-ng data is extracted from APK assets and
 * compiled on the first call to [init] (one-time,
 * persists across app launches).
 */
open class EspeakPhonemizer(
    context: Context,
    language: String = "en-us",
) : PhonemizerProvider {

    // Private Attributes
    // ------------------------------------------------------------------
    private val __language: String = language

    companion object {
        private const val TAG = "EspeakPhonemizer"
        private var __initialized = false
        private val __lock = Any()

        private val __punctuation: Set<Char> =
            setOf(
                ';', ':', ',', '.', '!', '?',
                '\u00A1', '\u00BF',  // ¡ ¿
                '\u2014', '\u2026',  // — …
                '"',
                '\u00AB', '\u00BB',  // « »
                '\u201C', '\u201D',  // " "
            )
    }

    // Constructor
    // ------------------------------------------------------------------
    init {
        __ensure_initialized(context, language)
    }

    // Public Methods
    // ------------------------------------------------------------------

    override fun phonemize(text: String): String {
        val preprocessed = preprocess(text)
        val raw =
            __phonemize_preserve_punct(preprocessed)
        val cleaned = clean(raw)
        Log.i(
            TAG,
            "phonemize input=${text.take(80)}\n " +
                "  preserve-punct=$raw\n " +
                "  cleaned=$cleaned"
        )
        return cleaned
    }

    open fun preprocess(text: String): String = text

    open fun clean(phonemes: String): String =
        phonemes

    // Private Methods — Initialization
    // ------------------------------------------------------------------

    private fun __ensure_initialized(
        context: Context,
        language: String
    ) {
        synchronized(__lock) {
            if (__initialized) return

            val espeak_root = File(
                context.filesDir, "espeak-ng"
            )
            espeak_root.mkdirs()

            val data_dir = File(
                espeak_root, "espeak-ng-data"
            )
            if (!data_dir.exists()) {
                __extract_assets(
                    context, espeak_root
                )
                __compile_data(espeak_root)
            }

            val ok = EspeakNg.nativeInitialize(
                espeak_root.absolutePath,
                language
            )
            if (!ok) {
                Log.e(TAG,
                    "espeak_Initialize failed")
                return
            }
            __initialized = true
        }
    }

    private fun __extract_assets(
        context: Context,
        root: File
    ) {
        val am = context.assets
        val dirs = listOf(
            "espeak-ng/espeak-ng-data",
            "espeak-ng/phsource",
            "espeak-ng/dictsource",
        )
        for (dir in dirs) {
            val target_name =
                dir.removePrefix("espeak-ng/")
            __copy_asset_dir(
                am, dir, File(root, target_name)
            )
        }
    }

    private fun __copy_asset_dir(
        am: android.content.res.AssetManager,
        asset_path: String,
        target_dir: File
    ) {
        val children: Array<String>
        try {
            children = am.list(asset_path)
                ?: return
        } catch (_: IOException) {
            return
        }

        if (children.isEmpty()) {
            // Leaf file — copy it
            target_dir.parentFile?.mkdirs()
            try {
                am.open(asset_path).use { input ->
                    FileOutputStream(
                        target_dir
                    ).use { output ->
                        input.copyTo(output)
                    }
                }
            } catch (e: IOException) {
                Log.e(TAG,
                    "Copy failed: $asset_path " +
                        "-> ${e.message}")
            }
            return
        }

        // Directory — recurse
        target_dir.mkdirs()
        for (child in children) {
            __copy_asset_dir(
                am,
                "$asset_path/$child",
                File(target_dir, child)
            )
        }
    }

    private fun __compile_data(root: File) {
        val phsource = File(
            root, "phsource"
        ).absolutePath
        val dictsource = File(
            root, "dictsource"
        ).absolutePath

        val ok = EspeakNg.nativeCompileData(
            root.absolutePath,
            phsource,
            dictsource
        )
        if (!ok) {
            Log.e(TAG,
                "espeak-ng data compilation failed")
        }
    }

    // Private Methods — Phonemization
    // ------------------------------------------------------------------

    /**
     * Phonemize with punctuation preservation,
     * matching Python `phonemizer` library's
     * `preserve_punctuation=True` and iOS
     * `EspeakPhonemizer.__phonemize_preserve_punct`.
     */
    private fun __phonemize_preserve_punct(
        text: String
    ): String {
        data class Segment(
            val content: String,
            val is_punct: Boolean,
        )

        val segments = mutableListOf<Segment>()
        var current = StringBuilder()
        var in_punct = false

        for (ch in text) {
            val is_p = ch in __punctuation
            if (is_p != in_punct &&
                current.isNotEmpty()
            ) {
                segments.add(
                    Segment(
                        current.toString(), in_punct
                    )
                )
                current = StringBuilder()
            }
            in_punct = is_p
            current.append(ch)
        }
        if (current.isNotEmpty()) {
            segments.add(
                Segment(
                    current.toString(), in_punct
                )
            )
        }

        val parts = mutableListOf<String>()
        for ((content, is_punct) in segments) {
            if (is_punct) {
                parts.add(content)
            } else {
                val trimmed = content.trim()
                if (trimmed.isEmpty()) continue
                val ph = __phonemize_raw(trimmed)
                if (ph.isEmpty()) continue
                val has_leading_space =
                    content.firstOrNull()
                        ?.isWhitespace() == true
                if (has_leading_space &&
                    parts.isNotEmpty()
                ) {
                    parts.add(" $ph")
                } else {
                    parts.add(ph)
                }
            }
        }

        return parts.joinToString("")
    }

    private fun __phonemize_raw(
        text: String
    ): String {
        return EspeakNg.nativeTextToPhonemes(text)
    }
}

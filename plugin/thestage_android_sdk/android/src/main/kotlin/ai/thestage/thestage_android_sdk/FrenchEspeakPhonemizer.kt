package ai.thestage.thestage_android_sdk

import android.content.Context

// ----------------------------------------------------------------------
// FrenchEspeakPhonemizer
// ----------------------------------------------------------------------
/**
 * French-specific phonemizer matching
 * `neutts.phonemizers.FrenchPhonemizer`.
 */
class FrenchEspeakPhonemizer(
    context: Context
) : EspeakPhonemizer(context, "fr-fr") {

    override fun clean(
        phonemes: String
    ): String {
        return phonemes.replace("-", "")
    }
}

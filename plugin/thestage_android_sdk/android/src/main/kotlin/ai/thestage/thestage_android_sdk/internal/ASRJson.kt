package ai.thestage.thestage_android_sdk.internal

import ai.thestage.qlip.models.asr.ASRResult
import ai.thestage.qlip.models.asr.ASRTurn
import ai.thestage.qlip.models.asr.json
import ai.thestage.qlip.models.asr.json_rows
import ai.thestage.qlip.models.asr.speaker.SpeakerSetup
import ai.thestage.qlip.models.asr.speaker.SpeakerVoices
import java.io.File

// ----------------------------------------------------------------------
// ASR JSON (plugin wire format)
// ----------------------------------------------------------------------
/**
 * The ASR payloads the plugin hands Dart. Keys match the Apple
 * plugin (`__encode_asr_result`, `ASRNodeEngineStream.encode`,
 * `ASRStreamHandler`), so the shared Dart types parse both.
 */
internal object ASRJson {

    /**
     * An [ASRResult]: the model API's row (`transcription`, `text`,
     * `token_count`, `decode_seconds`, `timestamp_mode`, `tokens`?,
     * `words`?, `language`?) plus `generated_tokens` and `metrics`.
     */
    fun result(r: ASRResult): Map<String, Any?> {
        val row = LinkedHashMap<String, Any?>(r.json_rows().first())
        row["generated_tokens"] = r.generated_tokens
        row["metrics"] = r.metrics.json()
        return row
    }

    /**
     * `TSASREngine`'s `speakers` key as a [SpeakerSetup]: `true` for
     * the defaults, or a map with any of `final_pass`, `diarizer`,
     * `speaker_model`, `diarizer_revision`, `speaker_model_revision`
     * and `voices_path` (a saved-voices file). Absent or `false`:
     * no speakers.
     */
    fun speaker_setup(value: Any?): SpeakerSetup? {
        if (value == true) return SpeakerSetup()
        val map = value as? Map<*, *> ?: return null
        fun str(key: String): String? =
            (map[key] as? String)?.takeIf { it.isNotEmpty() }
        val base = SpeakerSetup()
        return SpeakerSetup(
            voices = str("voices_path")?.let { SpeakerVoices(File(it)) },
            final_pass = map["final_pass"] as? Boolean
                ?: base.final_pass,
            diarizer = str("diarizer") ?: base.diarizer,
            speaker_model = str("speaker_model") ?: base.speaker_model,
            diarizer_revision = str("diarizer_revision")
                ?: base.diarizer_revision,
            speaker_model_revision = str("speaker_model_revision")
                ?: base.speaker_model_revision,
        )
    }

    /**
     * One [ASRTurn]: the field set both Flutter ASR surfaces emit,
     * plus `speaker_id` when a speaker session labelled the turn.
     */
    fun turn(t: ASRTurn): MutableMap<String, Any?> {
        val map = linkedMapOf<String, Any?>(
            "transcript" to t.transcript,
            "committed" to t.committed,
            "hypothesis" to t.hypothesis,
            "end_of_turn" to t.end_of_turn,
            "is_final" to t.end_of_turn,
        )
        t.speaker_id?.let { map["speaker_id"] = it }
        return map
    }

    /**
     * [value] in the types the standard message codec carries;
     * anything else crosses as its string form.
     */
    fun codec_safe(value: Any?): Any? = when (value) {
        null, is String, is Boolean, is Int, is Long, is Double ->
            value
        is Float -> value.toDouble()
        is Number -> value.toDouble()
        is Enum<*> -> value.name
        is Map<*, *> -> value.entries.associate {
            it.key.toString() to codec_safe(it.value)
        }
        is Iterable<*> -> value.map { codec_safe(it) }
        else -> value.toString()
    }
}

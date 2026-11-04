# Diarization (Who Spoke When / Who Said What)

Two models, one for each half of the question.

| Model | Answers | Owns engines |
|---|---|---|
| `nemotron-diarization` | **who spoke when** — speaker-labelled time segments | yes |
| `nemotron-multispeaker` | **who said what** — turns with text, plus a voice per speaker | no (composite) |

Use diarization alone for a speaker timeline. Use multispeaker when you
also want the words, and the speakers tied to people you have enrolled.

---

## Diarization

Streaming Sortformer. Segments **close as they end**, so during a
conversation you get committed turns rather than waiting for it to
finish.

```kotlin
TheStageAI.start_model(
    model_name = "diar",
    engines_path = "TheStageAI/Nemotron-3-Diarization",
)

// One-shot over a recording.
val rows = TheStageAI.infer(
    model_name = "diar",
    input_json = mapOf("audio" to samples),   // 16 kHz mono
)
```

Streaming uses the push contract from
[streaming.md](./streaming.md#streaming-input-asr): open with
`infer_stream`, push with `stream_append`, close with `stream_finish`.
Chunks carry `segments`, and `kind` says what they are:

| `kind` | `segments` holds |
|---|---|
| `committed` | segments that just closed — final, they will not change |
| `partial` | segments still running — will be superseded |
| `final` | every segment of the whole stream |
| `cancelled` | nothing; the session was abandoned |

Render `committed` as settled text and `partial` as provisional; a
partial is replaced by the next one, and eventually by a `committed`.

```kotlin
TheStageAI.infer_stream(
    model_name = "diar",
    input_json = mapOf("stream_id" to "turn-1"),
).collect { chunk ->
    chunk.segments?.forEach { seg ->
        println("${seg.speaker}: ${seg.start}..${seg.end}")
    }
}
```

Speaker labels (`SPEAKER_00`, `SPEAKER_01`, …) are **stable across the
recording** but arbitrary — they are not identities. For identities,
see multispeaker below.

---

## Multi-speaker transcription

A composite: it owns no engines and is assembled from models you
started yourself, so they keep their own lifetimes and can be shared
with the rest of your app.

```kotlin
// Start the components first — each is an ordinary model.
TheStageAI.start_model(model_name = "diar",  engines_path = "TheStageAI/Nemotron-3-Diarization")
TheStageAI.start_model(model_name = "embed", engines_path = "TheStageAI/redimnet2")
TheStageAI.start_model(model_name = "vad",   engines_path = "TheStageAI/silero-vad")
TheStageAI.start_model(model_name = "asr",   engines_path = "TheStageAI/thewhisper-large-v3-turbo")

// Then wire them.
TheStageAI.start_model(
    model_name = "meeting",
    model_type = "nemotron-multispeaker",
    engines_path = "",                      // composites have no bundle
    config = mapOf(
        "diarization" to "diar",
        "embedding" to "embed",
        "vad" to "vad",                     // required for streaming
        "asr" to "asr",                     // omit for turns without text
    ),
)
```

**Flutter:**

```dart
await TheStageFlutterSDK.start_nemotron_multispeaker(
  model_name: 'meeting',
  diarization_model: 'diar',
  embedding_model: 'embed',
  vad_model: 'vad',
  asr_model: 'asr',
);
```

`diarization` and `embedding` are required. Without `asr` you get turns
and no text; without `vad` the streaming path is unavailable.

### Enrolling speakers

Pass embeddings of people you already know and their turns come back
with `identity` set instead of an anonymous label. Vectors must come
from the **same embedder** the pipeline runs — a vector from another
model is meaningless here.

```kotlin
val rows = TheStageAI.infer(
    model_name = "meeting",
    input_json = mapOf(
        "audio" to samples,
        "enrolled" to listOf(
            mapOf("id" to "Ada", "vector" to ada_embedding),
        ),
    ),
)
```

To render a turn, show its identity when known and the anonymous label
otherwise: `turn.identity ?: turn.speaker` in Kotlin; in Dart,
`SpeakerTurn.displayName` does exactly that.

### Streaming chunk kinds

| `kind` | Carries |
|---|---|
| `utterance` | `turns` + `voices` of one committed utterance |
| `partial` | tentative turns of the open utterance (opt in with `partials: true`) |
| `identity_update` | `voices` whose identity or label changed |
| `reset` | a new speaker-cache epoch began |
| `final` | every speaker, plus the profile |
| `cancelled` | the session was abandoned |

`identity_update` is the one worth handling deliberately. Speakers are
decided incrementally, so two labels can later turn out to be one
person — the chunk's `delta` names the merge (`"SPEAKER_04->SPEAKER_01"`).
An app that has already drawn those turns should relabel them rather
than leave two speakers on screen that are the same person.

---

## Inputs / Outputs

| Field | Type | Notes |
|---|---|---|
| input `audio` | float list | 16 kHz mono, `[-1, 1]` |
| input `enrolled` | list | multispeaker only; `{"id", "vector"}` or `{"id", "vectors"}` |
| input `stream_id` | String | streaming only; identifies the session |
| output `segments` | list | `{start, end, speaker, identity?}` |
| output `turns` | list | multispeaker; a segment plus its `text` |
| output `voices` | list | multispeaker; speaker + embedding + identity |
| output `stage_profile` | map | per-stage timings, diagnostic only |

Audio is the same contract as the rest of the SDK: 16 kHz mono floats.
Resample before calling; nothing downstream will do it for you.

---

## Device notes

The diarization frontend (STFT, mel, projection) is native and runs per
80 ms frame. The model itself runs on the NPU; its bundles are
published for Snapdragon 8 Gen 2, 8 Gen 3, 8 Elite and 8 Elite Gen 5,
and there is no CPU bundle, so on other chips `start_model` fails —
see [model_management.md](./model_management.md).

The bundle is published and pinned by the SDK; rebuilding or
re-exporting it is not part of the public workflow. Contact
TheStage if you need a variant that is not published.

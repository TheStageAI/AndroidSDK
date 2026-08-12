# Speaker Embedding (Speaker ID)

On-device speaker embedding for enrollment and cosine verification.
The model is **ReDimNet2 B0**, shipped as `TheStageAI/redimnet2` and
addressed by model type `speaker-id`.

It maps a **2 s / 16 kHz mono** window to a **192-d, L2-normalized**
embedding; two utterances are compared by **cosine similarity**. The
model is a two-engine chain (a CPU mel front-end feeding the backbone)
that runs on **ORT-CPU** — it does not use the Snapdragon NPU, and at a
few milliseconds per call it doesn't need to.

## Basic Usage

**Kotlin** — via the singleton (auto-downloads the bundle):

```kotlin
import ai.thestage.qlip.TheStageAI

TheStageAI.registerContext(context)
TheStageAI.initialize(api_token = "your-api-token")

TheStageAI.start_model(
    model_name = "speaker_id",
    model_type = "speaker-id",
    engines_path = "TheStageAI/redimnet2",
)

// Enroll: audio only → embedding.
val enroll = TheStageAI.infer(
    model_name = "speaker_id",
    input_json = mapOf(
        "audio" to mapOf(
            "data" to pcm_16k_mono,   // FloatArray, samples in [-1, 1]
            "shape" to listOf(pcm_16k_mono.size),
            "dtype" to "float32",
        )
    )
)
val embedding = enroll[0]["embedding"] as List<Double>   // 192 floats

// Verify: audio + a reference embedding → also "similarity".
val check = TheStageAI.infer(
    model_name = "speaker_id",
    input_json = mapOf(
        "audio" to mapOf("data" to probe_pcm_16k_mono),
        "embedding" to mapOf("data" to embedding),
    )
)
val similarity = check[0]["similarity"] as Double        // cosine
```

**Flutter** — JSON path:

```dart
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');

await TheStageFlutterSDK.start_model(
  model_name: 'speaker_id',
  model_type: 'speaker-id',
  engines_path: 'TheStageAI/redimnet2',
);

// Enroll → embedding.
final enroll = await TheStageFlutterSDK.infer(
  model_name: 'speaker_id',
  input_json: {
    'audio': {'data': pcm16k, 'shape': [pcm16k.length], 'dtype': 'float32'},
  },
);
final embedding = (enroll[0]['embedding'] as List).cast<double>();

// Verify → similarity.
final check = await TheStageFlutterSDK.infer(
  model_name: 'speaker_id',
  input_json: {
    'audio': {'data': probePcm16k},
    'embedding': {'data': embedding},
  },
);
final similarity = check[0]['similarity'] as double;
```

## Audio contract

| Item | Value |
|---|---|
| Sample rate | **16 000 Hz** mono float (`FloatArray` / `Float32List`), samples in `[-1, 1]` |
| Window | **2.0 s** (32 000 samples). Any length in — longer is trimmed to the trailing window, shorter is left-zero-padded |
| Output dim | **192**, L2-normalized |
| Compute device | **CPU** (ORT) — the NPU is not used |

## Inputs / Outputs (JSON)

| Key | Direction | Type | Notes |
|---|---|---|---|
| `audio` | in | `{data, shape, dtype}` (or a bare float list) | Required |
| `embedding` | in | `{data: [Double]}` length 192 | Optional reference; when present, the response also carries `similarity` |
| `embedding` | out | `[Double]` length 192 | The probe embedding |
| `similarity` | out | `Double` | Cosine vs the reference (present only when a reference was supplied) |

The response is a single-element list. The caller chooses the accept
threshold; for raw same-speaker acceptance a value around **0.4** is a
reasonable starting point — tune it against your own audio and false-
accept tolerance. (The voice-agent speaker gate below uses a stricter
default of `0.75`.)

## Voice-Agent Speaker Gating

The voice agent can require **speaker verification** before it wakes,
so it only responds to an enrolled speaker. Configure it on the agent:

| Field | Type | Default | Description |
|---|---|---|---|
| `turn_start_mode` | String | `"vad"` | Set to `"vad_speaker_id_wake_word"` to require both a wake word **and** a matching speaker before leaving `sleeping` |
| `enrolled_speaker_embedding` | `[Double]` (192) | `null` | The reference embedding the incoming speaker is scored against |
| `speaker_similarity_threshold` | Double | `0.75` | Cosine at/above which the speaker is accepted |

Enroll (or re-enroll) the reference embedding on a running agent:

```kotlin
// embedding obtained from an earlier speaker_id infer() call.
agent.enroll_speaker(embedding)   // DoubleArray? — null clears enrollment
```

```dart
await agent.enrollSpeaker(embedding: embedding);   // List<double>?
```

`vad_speaker_id_wake_word` layers speaker verification on top of the
wake-word gate: the agent leaves `sleeping` only when the wake word
fires **and** the trailing speech scores at/above
`speaker_similarity_threshold` against the enrolled embedding. See
[voice_agent.md](./voice_agent.md) for the full agent surface.

## Agent checklist

- Model type `speaker-id`; common handle `speaker_id`; repo
  `TheStageAI/redimnet2`.
- Always 16 kHz mono float; 2 s window; 192-d output.
- Verify = audio + reference `embedding` → `similarity`; you pick the
  threshold.
- Runs on CPU — do not assume the NPU.

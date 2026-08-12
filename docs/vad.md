# SileroVAD (Voice Activity Detection)

Stateful per-chunk speech detection. Drives the gate between mic
capture and Whisper / TTS, or slices a longer recording into speech
regions in one batch call (see [Segment Extraction](#segment-extraction)).

VAD is reached through the singleton (JSON) path on both Kotlin and
Flutter — the response shape is identical.

## Basic Usage

**Kotlin:**

```kotlin
// build.gradle.kts: implementation(files("libs/TheStageCore.aar"))
import ai.thestage.qlip.TheStageAI

// Inside a coroutine (initialize / start_model / infer are suspend).
TheStageAI.registerContext(context)
TheStageAI.initialize(api_token = "your-api-token")

TheStageAI.start_model(
    model_name = "vad",
    engines_path = "TheStageAI/silero-vad"
)

// Process audio in 512-sample chunks (32 ms @ 16 kHz).
val result = TheStageAI.infer(
    model_name = "vad",
    input_json = mapOf("audio" to audio_chunk)   // FloatArray
)
val probability = result[0]["probability"] as Double
if (probability > 0.5) {
    println("Speech detected!")
}
```

**Flutter:**

```dart
import 'package:thestage_android_sdk/thestage_android_sdk.dart';
import 'dart:typed_data';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');

await TheStageFlutterSDK.start_model(
  model_name: 'vad',
  engines_path: 'TheStageAI/silero-vad',
);

// audio_chunk: Float32List, 16 kHz mono, exactly 512 samples.
final result = await TheStageFlutterSDK.infer(
  model_name: 'vad',
  input_json: {'audio': audio_chunk},
);
final probability = result[0]['probability'] as double;
if (probability > 0.5) {
  print('Speech detected!');
}
```

## Inputs / Outputs (single-chunk mode)

| Direction | Type | Description |
|---|---|---|
| input  `audio` | `FloatArray` | 16 kHz mono PCM, **exactly 512 samples** (32 ms). |
| input  `reset_state` | `Boolean` (default `false`) | Reset the LSTM state between independent utterances. |
| output `probability` | `Double` | Speech probability in `[0.0, 1.0]`. |

The single-chunk path returns just the probability — apply your own
threshold and hysteresis.

## Audio I/O

- 16 kHz mono `FloatArray`, samples in `[-1.0, 1.0]`.
- **Chunk size:** exactly 512 samples per `infer` call. Smaller chunks
  are zero-padded to 512 internally; larger chunks are rejected.
- **Stateful.** The model keeps an LSTM hidden state across calls.
  Pass `"reset_state": true` between independent utterances (or call
  `reset_state()` on the direct `SileroVAD` API).
- **Internal context.** A 64-sample carry-over from the previous chunk
  is prepended automatically — you don't need to overlap your capture
  yourself.

VAD runs on ORT-CPU on Android (it is a small stateful LSTM that does
not benefit from the Hexagon NPU). See
[Audio I/O Contract](./README.md#audio-io-contract) for the shared
format used across VAD / ASR / TTS.

## Real-Time Usage Pattern

**Kotlin:**

```kotlin
val threshold = 0.5
val speechBuffer = ArrayList<Float>()

for (chunk in microphoneStream) {               // 512 samples each
    val result = TheStageAI.infer(
        model_name = "vad",
        input_json = mapOf("audio" to chunk)
    )
    val probability = result[0]["probability"] as Double

    if (probability > threshold) {
        speechBuffer.addAll(chunk.toList())
    } else if (speechBuffer.isNotEmpty()) {
        // End of utterance — send to ASR.
        val transcript = TheStageAI.infer(
            model_name = "stt",
            input_json = mapOf("audio" to speechBuffer.toFloatArray())
        )
        speechBuffer.clear()
    }
}
```

**Flutter:**

```dart
const threshold = 0.5;
final speechBuffer = <double>[];

await for (final Float32List chunk in microphoneStream) {  // 512 samples each
  final result = await TheStageFlutterSDK.infer(
    model_name: 'vad',
    input_json: {'audio': chunk},
  );
  final probability = result[0]['probability'] as double;

  if (probability > threshold) {
    speechBuffer.addAll(chunk);
  } else if (speechBuffer.isNotEmpty()) {
    final pcm = Float32List.fromList(speechBuffer);
    await TheStageFlutterSDK.infer(
      model_name: 'stt',
      input_json: {'audio': pcm},
    );
    speechBuffer.clear();
  }
}
```

For a production speech gate (onset/offset frames, pre-roll, max
accumulation, speculative ASR) use `TheStageVoiceAgent` — its VAD node
already implements all of this, including segment endpointing with
hysteresis. See [voice_agent.md](./voice_agent.md).

## Segment Extraction

For a whole recording, hand the entire buffer to `infer` with
`extract_segments: true` and read back the speech spans as sample
indices — the SDK runs the model over the buffer and applies
onset/offset hysteresis + padding for you.

**Kotlin:**

```kotlin
val segments = TheStageAI.infer(
    model_name = "vad",
    input_json = mapOf(
        "audio" to recording,          // FloatArray, 16 kHz mono
        "extract_segments" to true,
        "min_silence_duration_ms" to 100,
    )
)
for (seg in segments) {
    val start = seg["start"] as Int    // sample indices
    val end = seg["end"] as Int
    val speech = recording.copyOfRange(start, end)
}
```

**Flutter:**

```dart
final segments = await TheStageFlutterSDK.infer(
  model_name: 'vad',
  input_json: {
    'audio': recording,                // Float32List, 16 kHz mono
    'extract_segments': true,
  },
);
for (final seg in segments) {
  final start = seg['start'] as int;   // sample indices
  final end = seg['end'] as int;
}
```

| Param | Type | Default | Meaning |
|---|---|---|---|
| `extract_segments` | `Boolean` | `false` | Switch `infer` into batch segment mode. |
| `threshold` | `Double` | `0.5` | Onset probability threshold. |
| `neg_threshold` | `Double` | auto | Offset threshold; `< 0` ⇒ `max(threshold − 0.15, 0.01)`. |
| `min_speech_duration_ms` | `Int` | `250` | Drop spans shorter than this. |
| `min_silence_duration_ms` | `Int` | `100` | Silence needed to end a span. |
| `speech_pad_ms` | `Int` | `30` | Padding grown around each span. |

Output is one `{ "start": Int, "end": Int }` per span (sample indices
into the input buffer). From Kotlin you can also call
`SileroVAD.extract_segments(...)` directly for a `List<SpeechSegment>`.

For a streaming, turn-level speech gate (onset/offset frames, pre-roll,
max accumulation, speculative ASR) use `TheStageVoiceAgent` instead —
its VAD node does live endpointing. `WhisperPipeline` also runs an
internal Silero pre-pass before transcribing.

## Cleanup

**Kotlin:**

```kotlin
TheStageAI.stop_model(model_name = "vad")
```

**Flutter:**

```dart
await TheStageFlutterSDK.stop_model(model_name: 'vad');
```

# Whisper ASR (Speech-to-Text)

On-device speech recognition using Whisper. The ASR pipeline handles
mel-spectrogram, encoder and decoder, with automatic VAD chunking and
long-audio stitching.

Flutter consumers go through the singleton `start_model` + `infer`
JSON path — there is no direct pipeline constructor on Dart. Both
surfaces share the same on-disk cache and response shape.

## Basic Usage

**Kotlin** — via the singleton (recommended; auto-downloads the bundle):

```kotlin
// build.gradle.kts: implementation(files("libs/TheStageCore.aar"))
import ai.thestage.qlip.TheStageAI

// Inside a coroutine (initialize / start_model / infer are suspend).
TheStageAI.registerContext(context)
TheStageAI.initialize(api_token = "your-api-token")

TheStageAI.start_model(
    model_name = "stt",
    engines_path = "TheStageAI/thewhisper-large-v3-turbo"  // HF repo or local
)

// Transcribe audio (16 kHz mono FloatArray, see Audio I/O Contract).
val json = TheStageAI.infer(
    model_name = "stt",
    input_json = mapOf("audio" to audio_samples, "language" to "en")
)
println(json[0]["transcription"])  // "Hello, how are you today?"
```

The direct Kotlin classes (`WhisperModel` + `TheStageASRPipeline`) are
also available for a local (already-downloaded) engines directory. They
load from a local dir — they do not download, so `prefetch_model` first:

```kotlin
import ai.thestage.qlip.models.whisper.WhisperModel
import ai.thestage.qlip.models.asr.TheStageASRPipeline

val dir = TheStageAI.prefetch_model(
    repo_id = "TheStageAI/thewhisper-large-v3-turbo"
)

val engine = WhisperModel(engines_path = dir, device = "npu")
val stt    = TheStageASRPipeline.wrap(engine)

val result = stt.infer(audio = audio_samples, language = "en")
println(result.text)               // result.tokens_per_second, ...
```

**Flutter** — JSON path:

```dart
import 'package:thestage_android_sdk/thestage_android_sdk.dart';
import 'dart:typed_data';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');

await TheStageFlutterSDK.start_model(
  model_name: 'stt',
  engines_path: 'TheStageAI/thewhisper-large-v3-turbo',
);

// audio_samples: Float32List, 16 kHz mono, samples in [-1.0, 1.0].
final result = await TheStageFlutterSDK.infer(
  model_name: 'stt',
  input_json: {
    'audio': audio_samples,
    'language': 'en',
  },
);
print(result[0]['transcription']);
```

## Inputs / Outputs

| Direction | Type | Description |
|---|---|---|
| input  `audio` | `FloatArray` | 16 kHz mono PCM, samples in `[-1.0, 1.0]`, any length. |
| input  `language` | `String` (default `"en"`) | Whisper language code: `en`, `fr`, `de`, `es`, `pt`, `ja`, `ko`, `zh`, `ar`, `hi`, `ru`, … |
| input  `config.max_new_tokens` | `Int?` | Cap per-window decode. |
| input  `config.return_tokens` | `Boolean` (default `false`) | **Direct Kotlin API only** — include token IDs in `ASRResult.tokens`. Not honored on the singleton / JSON path. |
| output `ASRResult.text` | `String` | Transcribed text. |
| output `ASRResult.token_count` | `Int` | Total decoded tokens (sum across windows). |
| output `ASRResult.decode_seconds` | `Double` | Decoder wall time. |
| output `ASRResult.tokens` | `IntArray?` | Token IDs (only if `return_tokens == true`). |

> The output rows above (`token_count`, `decode_seconds`, `tokens`) and
> `return_tokens` are the **direct Kotlin `TheStageASRPipeline` /
> `ASRResult`** surface. The singleton / JSON path returns a different
> key set — see [Singleton API](#singleton-api-thestageai) below.

## Audio I/O

- 16 kHz mono `FloatArray`, samples normalized to `[-1.0, 1.0]`.
- Long buffers are split internally into the bundle's `chunk_seconds`
  windows. The shipped bundle sets its transcription window (see the
  bundle's `encoder_spec.json`); the SDK default is **30 s**, and other
  window sizes (10 / 15 / 30 s exports) work the same way.
- Overlap between windows is configurable via the `overlap_seconds`
  constructor argument (default `0`). Useful on streaming captures to
  avoid losing words straddling a chunk boundary.
- Mismatched-rate input is **not** auto-resampled — convert your mic
  capture to 16 kHz mono Float before calling `infer`.

See [Audio I/O Contract](./README.md#audio-io-contract) for the
shared format used across VAD / ASR / TTS.

## Streaming (live transcription)

Live, push-based transcription — feed mic audio as it arrives and read
stable, monotonically-growing partials — is available on Android
through the **Voice Agent** ([voice_agent.md](./voice_agent.md)), which
runs streaming ASR internally: it re-decodes the growing turn buffer on
a single serial worker and commits stable text via LocalAgreement, so
captions never flicker or retract, and the authoritative end-of-turn
transcript always covers the complete utterance (including the last
word). There is no standalone streaming-ASR entry point on the direct
pipeline; use the batch `infer` above for one-shot transcription and
the Voice Agent for real-time captioning.

## Internal VAD Chunking

The Whisper pipeline includes a Silero-VAD pre-pass that finds speech
segments before transcribing — this is the "automatic VAD chunking"
referenced above. It is active whenever the bundle ships a `vad`
sub-engine; a bundle without one falls back to fixed-length window
chunking. The pre-pass is driven purely by bundle contents.

## Singleton API (`TheStageAI`)

`TheStageAI` is a Kotlin `object` (singleton); its methods are
`suspend`.

```kotlin
TheStageAI.start_model(
    model_name = "stt",                            // any handle you choose
    engines_path = "TheStageAI/thewhisper-large-v3-turbo"
)

val json = TheStageAI.infer(
    model_name = "stt",
    input_json = mapOf(
        "audio" to audio_samples,   // FloatArray, 16 kHz mono
        "language" to "en"          // optional, default "en"
    )
)
val text = json[0]["transcription"] as String
```

JSON response keys: `transcription` (`String`), `mel_seconds`
(`Double`), `encoder_seconds` (`Double`), `total_seconds` (`Double`),
`tokens_per_second` (`Double`), `generated_tokens` (`Int`).

The Flutter `TheStageFlutterSDK.infer` call hits this exact JSON path,
so the response keys above apply unchanged on Dart. `audio` crosses
the platform channel as `Float32List`; do not promote to `Float64List`.

## Full Constructor

```kotlin
val engine = WhisperModel(
    engines_path = dir,                  // local (prefetched) dir
    device = "npu",                      // "npu" | "gpu" | "cpu"
    overlap_seconds = 0.0                // chunk overlap for long audio
)
val stt = TheStageASRPipeline.wrap(engine)
```

Per-module device placement (mel on CPU, encoder / decoder on NPU) is
set in the bundle's `metadata.json`; the top-level `device` is a coarse
default. When downloading through the singleton, pass per-module
overrides via `start_model(devices = mapOf("encoder" to "npu", ...))`.
`TheStageAI.initialize(...)` must have succeeded before either call.

## Load Progress

Download / extract / load progress is reported through the singleton
and Flutter entry points via an optional `on_load_progress` handler
that fires through four phases with a monotonic `fraction` in
`0.0 .. 1.0`:

```kotlin
TheStageAI.start_model(
    model_name = "stt",
    engines_path = "TheStageAI/thewhisper-large-v3-turbo",
    on_load_progress = { p ->
        // p.phase ∈ { DOWNLOADING, EXTRACTING, LOADING, READY }
        println("[${p.model}] ${p.phase} ${(p.fraction * 100).toInt()}%")
    }
)
```

The same `on_load_progress` parameter is accepted by
`TheStageAI.prefetch_model(...)`. For the full event contract see
[Load Progress in the index](./README.md#load-progress).

**Flutter:**

```dart
TheStageFlutterSDK.on_progress.listen((event) {
  if (event['model_name'] != 'stt') return;
  final phase    = event['phase']    as String?;   // downloading | extracting | loading | ready
  final fraction = event['progress'] as double?;   // 0.0 ... 1.0, monotonic
  print('[stt] $phase ${(fraction ?? 0) * 100}%');
});

await TheStageFlutterSDK.start_model(
  model_name: 'stt',
  engines_path: 'TheStageAI/thewhisper-large-v3-turbo',
);
```

## Prefetch Engines

```kotlin
val engines_dir = TheStageAI.prefetch_model(
    repo_id = "TheStageAI/thewhisper-large-v3-turbo"
)

// Later — instant load, no network:
val engine = WhisperModel(engines_path = engines_dir)
```

## Cleanup

When you used the singleton API:

```kotlin
TheStageAI.stop_model(model_name = "stt")
```

**Flutter:**

```dart
await TheStageFlutterSDK.stop_model(model_name: 'stt');
```

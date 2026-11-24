# Whisper ASR (Speech-to-Text)

On-device speech recognition using Whisper (large-v3-turbo). The ASR
pipeline handles mel-spectrogram, encoder and decoder, with automatic
VAD chunking and long-audio stitching. The encoder and decoder run on
the Hexagon NPU through TheStage's own NPU runtime.

Usage (batch `infer`, live captions, word timestamps, language
detection, configuration) is on [asr.md](./asr.md). This page covers
what is specific to the Whisper bundle.

## Basic Usage

**Kotlin**

```kotlin
import ai.thestage.qlip.TheStageAI
import ai.thestage.qlip.models.asr.ASRGenerationConfig

// Inside a coroutine (initialize / start_model / infer are suspend).
TheStageAI.registerContext(context)
TheStageAI.initialize(api_token = "your-api-token")

TheStageAI.start_model(
    model_name = "stt",
    engines_path = "TheStageAI/thewhisper-large-v3-turbo"  // HF repo or local
)

// 16 kHz mono FloatArray, see the audio contract on asr.md.
val result = TheStageAI.asr_engine(stt = "stt")
    .infer(audio_samples, ASRGenerationConfig(language = "en"))
println(result.text)
```

**Flutter**

```dart
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');

await TheStageFlutterSDK.start_model(
  model_name: 'stt',
  engines_path: 'TheStageAI/thewhisper-large-v3-turbo',
);

// audio_samples: Float32List, 16 kHz mono, samples in [-1.0, 1.0].
final result = await ASREngine(stt: 'stt').infer(
  audio_samples,
  config: const ASRGenerationConfig(language: 'en'),
);
print(result.text);
```

## JSON rows

`TheStageAI.infer` / `TheStageFlutterSDK.infer` on a Whisper model take
`audio` plus the `ASRGenerationConfig` keys (`language`, `timestamps`,
`max_new_tokens`, `return_tokens`, `text_context`, `context_text`,
`language_detection`, `overlap`; see [asr.md](./asr.md#transcribe-audio)).
A payload without `timestamps` gets `WORD`. With `vad_model_name` (a
started Silero VAD) the Flutter call runs through `ASREngine(stt, vad)`.

The single row carries the `ASRResult` keys of
[asr.md](./asr.md#result-object) (`transcription`, `text`, `words`,
`language`, `timestamp_mode`, `token_count`, `generated_tokens`,
`decode_seconds`, `tokens`, `metrics`) plus `language_code`,
`mel_seconds`, `encoder_seconds`, `total_seconds` and
`tokens_per_second`.

## Windows and VAD

- Long audio is cut into the bundle's windows: **10 s** for the shipped
  bundle (`encoder_spec.json`), with `overlap` (default `0.2`) reused
  by the next window.
- When the bundle ships a `vad` sub-engine, `infer` on the model moves
  window cuts into confirmed silence and skips windows without speech,
  as `ASREngine` does with a VAD.
- Mismatched-rate input is **not** resampled: convert to 16 kHz mono
  float first.

## Direct pipeline

`WhisperPipeline` wraps a loaded `WhisperModel` from a local
(already-downloaded) engines directory; `TheStageAI.asr_pipeline(
model_name)` returns the one of a started model.

```kotlin
import ai.thestage.qlip.models.asr.ASREngine
import ai.thestage.qlip.models.asr.whisper.WhisperPipeline
import ai.thestage.qlip.models.whisper.WhisperModel

val dir = TheStageAI.prefetch_model(
    repo_id = "TheStageAI/thewhisper-large-v3-turbo"
)
val engine = WhisperModel(engines_path = dir, device = "npu")
val stt = ASREngine(WhisperPipeline(engine))
```

Placement comes from the bundle: the mel front-end runs on the CPU and
the encoder and decoder on the NPU. `device` and the singleton's
per-module `devices` overrides are accepted for call-site
compatibility; the shipped bundle's NPU passes ignore them.
`TheStageAI.initialize(...)` must have succeeded first.

## Load Progress

Download / extract / load progress is reported through the singleton
and Flutter entry points via an optional `on_load_progress`
handler. `phase` is the signal; `fraction` is non-null only
while downloading, where it runs `0.0 .. 1.0`:

```kotlin
TheStageAI.start_model(
    model_name = "stt",
    engines_path = "TheStageAI/thewhisper-large-v3-turbo",
    on_load_progress = { p ->
        // p.phase ∈ { DOWNLOADING, WAITING_FOR_WIFI,
        //            WAITING_FOR_CONFIRMATION, EXTRACTING,
        //            LOADING, READY }
        val pct = p.fraction?.let { " ${(it * 100).toInt()}%" } ?: ""
        println("[${p.model}] ${p.phase}$pct")
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
  // phase: downloading | waiting_for_wifi |
  //        waiting_for_confirmation | extracting | loading | ready
  final phase    = event['phase']    as String?;
  // Present only while downloading. Null => show an
  // indeterminate indicator; do NOT fall back to 0.
  final fraction = event['progress'] as num?;
  final pct = fraction == null
      ? ''
      : ' ${(fraction * 100).toStringAsFixed(0)}%';
  print('[stt] $phase$pct');
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
val stt = ASREngine(WhisperPipeline(engine))
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

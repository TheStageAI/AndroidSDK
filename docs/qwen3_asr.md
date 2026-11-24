# Qwen3-ASR (Speech-to-Text)

On-device speech recognition with Qwen3-ASR-0.6B in 30 languages, with
language detection. The audio encoder and the decoder run on the
Hexagon NPU through TheStage's own NPU runtime.

Usage (batch `infer`, live captions, word timestamps, language
detection, configuration) is on [asr.md](./asr.md). This page covers
what is specific to the Qwen3-ASR bundle.

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
    engines_path = "TheStageAI/Qwen3-ASR-0.6B"  // HF repo or local
)

// 16 kHz mono FloatArray, see the audio contract on asr.md.
val result = TheStageAI.asr_engine(stt = "stt")
    .infer(audio_samples, ASRGenerationConfig(language = "auto"))
println("${result.language}: ${result.text}")
```

**Flutter**

```dart
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');

await TheStageFlutterSDK.start_model(
  model_name: 'stt',
  engines_path: 'TheStageAI/Qwen3-ASR-0.6B',
);

// audio_samples: Float32List, 16 kHz mono, samples in [-1.0, 1.0].
final result = await ASREngine(stt: 'stt').infer(
  audio_samples,
  config: const ASRGenerationConfig(language: 'auto'),
);
print('${result.language}: ${result.text}');
```

## Languages

`language` takes `auto` or one of these ISO codes; any other code fails
with `LANGUAGE_UNSUPPORTED`.

| Code | Language | Code | Language | Code | Language |
|---|---|---|---|---|---|
| `ar` | Arabic | `fr` | French | `pl` | Polish |
| `cs` | Czech | `hi` | Hindi | `pt` | Portuguese |
| `da` | Danish | `hu` | Hungarian | `ro` | Romanian |
| `de` | German | `id` | Indonesian | `ru` | Russian |
| `el` | Greek | `it` | Italian | `sv` | Swedish |
| `en` | English | `ja` | Japanese | `th` | Thai |
| `es` | Spanish | `ko` | Korean | `tr` | Turkish |
| `fa` | Persian | `mk` | Macedonian | `vi` | Vietnamese |
| `fi` | Finnish | `ms` | Malay | `yue` | Cantonese |
| `fil` | Filipino | `nl` | Dutch | `zh` | Chinese |

- **`auto`**: the model names the language before it writes the text,
  in the same decode, so detection costs nothing extra.
  `result.language` is the ISO code of that language. On audio longer
  than one window, each window detects its own language, and
  `result.language` is the last window's.
- **A code**: the decode is forced into that language and
  `result.language` is that code. The code is not checked against the
  audio, so pass one only when you know the language.
- **Silence or non-speech** gives empty text.

## Word timestamps

`timestamps: WORD` (the default) returns every word with `t0` / `t1`,
but the times are **estimated**: each window's words are spread evenly
over that window. Use them to show roughly where a word falls, not to
seek to it exactly. `ASRCapabilities.measured_word_times` is `false`
for this model.

For live captions this means the `NAIVE` commit policy (see
[asr.md](./asr.md#configuration)): words commit once repeated decodes
agree on them, and a turn ends after 3.5 s of silence
(`endpoint_silence_s`). `THESTAGE_V5` and `THESTAGE_V6` need measured
word times and fail at open on this model.

## JSON rows

`TheStageAI.infer` / `TheStageFlutterSDK.infer` on a Qwen3-ASR model
take `audio` plus the `ASRGenerationConfig` keys (see
[asr.md](./asr.md#transcribe-audio)). A payload without `language` gets
`auto`. The single row carries the `ASRResult` keys of
[asr.md](./asr.md#result-object) plus `generated_tokens` and `metrics`.

`load_components` / `unload_components` with `qwen3-asr` (or `all`)
load or free the encoder and the decoder together.

## Windows

- Long audio is cut into **30 s** windows (the bundle's
  `max_window_s`), with `overlap` (default `0.2`) reused by the next
  window.
- With a VAD (`ASREngine(stt, vad)`), window cuts move into confirmed
  silence and windows without speech are skipped.
- Mismatched-rate input is **not** resampled: convert to 16 kHz mono
  float first.

## Load Progress, Prefetch, Cleanup

The same as for every ASR model: `on_load_progress` on `start_model` /
`prefetch_model` ([whisper.md](./whisper.md#load-progress),
[README.md](./README.md#load-progress)), `TheStageAI.prefetch_model(
repo_id = "TheStageAI/Qwen3-ASR-0.6B")` to download ahead, and
`stop_model(model_name = "stt")` to free it.

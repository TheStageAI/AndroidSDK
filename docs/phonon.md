# Phonon and Pocket TTS (Text-to-Speech)

On-device text-to-speech from small flow-matching models: a language
model emits one audio latent every 80 ms and a streaming decoder turns
it into 24 kHz audio. Both run on the NPU. One public pipeline,
`PhononTTSPipeline`, serves every model below.

## Models

| HF repo | `model_type` | Language | Voices (default first) |
|---|---|---|---|
| `TheStageAI/phonon-31m-en` | `phonon` | English | `default`, `easton`, `zoey`, `harper`, `maeve`, `freya`, `azelma` |
| `TheStageAI/pocket-tts-18m-en` | `pocket-tts` | English | `azelma`, `alba`, `charles`, `cosette`, `javert`, `marius` |
| `TheStageAI/pocket-tts-100m-fr` | `pocket-tts` | French | `estelle`, then the six English voices |
| `TheStageAI/pocket-tts-100m-de` | `pocket-tts` | German | `juergen`, then the six English voices |
| `TheStageAI/pocket-tts-100m-it` | `pocket-tts` | Italian | `giovanni`, then the six English voices |
| `TheStageAI/pocket-tts-100m-es` | `pocket-tts` | Spanish | `lola`, then the six English voices |
| `TheStageAI/pocket-tts-100m-pt` | `pocket-tts` | Portuguese | `rafael`, then the six English voices |
| `TheStageAI/pocket-tts-100m-nl` | `pocket-tts` | Dutch | `daan`, then the six English voices |
| `TheStageAI/pocket-tts-100m-ja` | `pocket-tts` | Japanese | the six English voices |
| `TheStageAI/pocket-tts-100m-zh` | `pocket-tts` | Chinese (Mandarin) | the six English voices |
| `TheStageAI/pocket-tts-100m-ko` | `pocket-tts` | Korean | the six English voices |
| `TheStageAI/pocket-tts-100m-hi` | `pocket-tts` | Hindi | the six English voices |
| `TheStageAI/pocket-tts-100m-pl` | `pocket-tts` | Polish | `shefowl`, then the six English voices |
| `TheStageAI/pocket-tts-100m-tr` | `pocket-tts` | Turkish | `female_1`, `female_2`, `female_3`, `male_1`, `male_2`, `male_3`, then the six English voices |
| `TheStageAI/pocket-tts-100m-el` | `pocket-tts` | Greek | `athina`, `eleni`, `giorgos`, `katerina`, `kostas`, `nikos`, `sophia`, `spyros`, then the six English voices |
| `TheStageAI/pocket-tts-100m-ru` | `pocket-tts` | Russian | the six English voices |

"The six English voices" are Pocket 18M's: `azelma`, `alba`,
`charles`, `cosette`, `javert`, `marius`. In a language model they
speak that language in an English speaker's voice, which can carry an
English accent; the language's own voice comes first and is the
default.

Japanese, Chinese, Korean, Hindi, Polish, Turkish, Greek and Russian
are community fine-tunes of Pocket TTS, each published under its
author's license (see the HF model card). Their text contracts:

- Japanese and Chinese take ordinary written text (kanji, kana, Han
  characters); numbers and symbols are expanded, nothing is
  romanised.
- Hindi takes Devanagari without punctuation: the SDK removes it
  before synthesis, and Latin letters and digits are spelled out in
  Devanagari.
- Russian expects stress marks (U+0301 after the stressed vowel, as
  in `Здра́вствуйте`); the SDK passes them through.

The SDK resolves `model_type` from the repo id, so pass it only for a
local bundle. The models run on Snapdragon 8 Gen 2, 8 Gen 3, 8 Elite
and 8 Elite Gen 5.

## Basic Usage

**Kotlin**, through the singleton (downloads the bundle on first use):

```kotlin
import ai.thestage.qlip.TheStageAI

// Inside a coroutine (initialize / start_model / infer are suspend).
TheStageAI.registerContext(context)
TheStageAI.initialize(api_token = "your-api-token")

val status = TheStageAI.start_model(
    model_name = "tts",
    engines_path = "TheStageAI/pocket-tts-100m-fr",
)
val voices = status.voices          // ["estelle", "azelma", ...]

val json = TheStageAI.infer(
    model_name = "tts",
    input_json = mapOf("text" to "Bonjour tout le monde."),
)
// Batch audio arrives as List<Double>: 24 kHz mono PCM.
val audio = (json[0]["audio"] as List<Double>)
    .map { it.toFloat() }.toFloatArray()
val sampleRate = json[0]["sample_rate"] as Int   // 24000
```

**Kotlin**, through the pipeline class. `create` takes a repo id or a
local bundle:

```kotlin
import ai.thestage.qlip.models.phonon.PhononTTSPipeline
import ai.thestage.qlip.models.tts.TTSGenerationConfig

val tts = PhononTTSPipeline.create(
    engines_path = "TheStageAI/phonon-31m-en",
    voice_id = "zoey",
)
val result = tts.infer("Hello, world!")
val pcm = result.audio                 // FloatArray, 24 kHz mono
tts.close()
```

**Flutter**, the JSON path:

```dart
import 'package:thestage_android_sdk/thestage_android_sdk.dart';
import 'dart:typed_data';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');

await TheStageFlutterSDK.start_model(
  model_name: 'tts',
  engines_path: 'TheStageAI/pocket-tts-18m-en',
  config: {'voice_id': 'alba'},
);

final result = await TheStageFlutterSDK.infer(
  model_name: 'tts',
  input_json: {'text': 'Hello, world!'},
);
final audio = Float32List.fromList(
    (result[0]['audio'] as List).cast<double>());
```

## Start Config

| Key | Meaning |
|---|---|
| `voice_id` | A voice of the bundle; empty or absent is the default voice |
| `voice_dir` | A [voice folder](#custom-voices) outside the bundle; wins over `voice_id` |
| `language` | ISO 639-1 code for the text normaliser; default is the voice's language, else the model's |

`ModelStatus.voices` lists the bundle's voices, the default first.

## Inputs / Outputs

`infer` and `infer_stream` take:

| Key | Type | Meaning |
|---|---|---|
| `text` | `String` | Text to synthesize (required) |
| `seed` | `Int` | Deterministic noise; same seed and text give the same audio |
| `temperature` | `Double` | Noise level, `0`–`2`; default is the model's (0.3); `0` is deterministic |
| `voice_id` | `String` | Switches to this bundle voice before the call |
| `language` | `String` | Switches the normaliser's language before the call |
| `output_sample_rate` | `Int` | Resample to this rate (8000–192000); default 24000 |

`infer_stream` also takes `frames_per_chunk` (1–64, default 4: audio
per chunk in 80 ms frames), `first_frames_per_chunk` (default 1, so the
first audio arrives after one frame), `realtime_gate` (default `true`:
generation stays about `realtime_lead_ms`, default 2000, ahead of
playback instead of running at full speed) and `realtime_lead_ms`.

`infer` returns one map: `audio` (`List<Double>`), `sample_rate`,
`duration` (seconds), `frames`, `stop_reason` (`eos` when the model
ended the speech), `rtf` (audio seconds per wall second) and stage
timings. `infer_stream` emits `kind = "audio"` chunks with `audio`
(`FloatArray`) and `sample_rate`; the last one is `is_final` and
carries `stop_reason`.

## Streaming

`infer_stream` takes the whole text. For text that arrives in pieces
(an LLM's reply, say), open a push streamer: it synthesizes each
sentence as soon as it is complete.

```kotlin
val streamer = TheStageAI.open_tts_streamer(model_name = "tts")
scope.launch {
    streamer.output.collect { chunk ->
        chunk.audio?.let { player.write(it) }   // FloatArray, 24 kHz
    }
}
streamer.send("The first sentence arrives. ")
streamer.send("Then a second one")
streamer.finish()
```

In Flutter, push mode is the `tts_stream` channel's `stream_mode:
"push"`, the same as for NeuTTS ([streaming.md](./streaming.md)).

## Voices

```kotlin
tts.set_voice(voice_id = "alba")                    // a bundle voice
tts.set_voice(voice_dir = "/path/to/my_voice")      // a voice folder
tts.set_voice(voice_id = tts.voice_id, language = "fr")
```

`set_voice` installs the voice in a few milliseconds without reloading
the model. An unknown voice throws and keeps the active one. Through
the singleton, pass `voice_id` / `language` with a call, or restart the
model with `voice_dir` in its config.

## Custom Voices

A voice is a folder holding a precomputed prompt for one model: the
model's state after it has listened to the speaker. The SDK does not
make voices from audio. A folder works only with the model it was made
for: the SDK checks the model fingerprint in `voice.json` and refuses a
voice made for another model, so each language model needs its own
copy of a voice.

`voice.json` holds `frames`, `layers`, `kv_dim` and `weights_sha256`
(at the top level, or in a `kv_prefix` object), and optionally `name`
and `language`. The prompt itself is either

- `voice.safetensors` beside it, with `key` and `value` tensors (fp16,
  `[layers, kv_dim, frames]`): the layout of the bundles' own voices;
  or
- a raw fp16 file of K then V, each `[layers, kv_dim, frames]`, named
  by `kv_file` (or `kv_prefix.file`): the iOS SDK's voice layout, so
  one voice folder serves both platforms.

The voice id of a folder is its name.

## Cleanup

```kotlin
TheStageAI.stop_model("tts")       // the singleton
tts.close()                        // a PhononTTSPipeline
```

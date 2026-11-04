# NeuTTS (Text-to-Speech)

On-device neural text-to-speech with batch and push-based streaming.
Two public pipelines:

- **`NeuTTSMultilingual`** — Qwen3-based, 9 languages.
- **`NeuTTS`** (nano) — phoneme-based, English only.

## Models

| HF repo | Pipeline | Languages | Voice packs |
|---|---|---|---|
| `TheStageAI/neutts-nano-multilingual` | `NeuTTSMultilingual` | the 9 [languages](#voices-and-languages) | yes |
| `TheStageAI/neutts-multilingual` | `NeuTTSMultilingual` | the 9 [languages](#voices-and-languages) | yes |
| `TheStageAI/neutts` | `NeuTTS` (nano) | English | no |

All three are `model_type` `neutts`; the SDK picks the pipeline from
the bundle. `neutts-nano-multilingual` is the smaller, faster
multilingual model and the one the example apps load; the examples on
this page use `neutts-multilingual`, and every call works the same on
either.

Flutter consumers go through the singleton `start_model` + `infer` /
`infer_stream` (JSON) path — there is no direct TTS pipeline
constructor on Dart. Both surfaces share the same on-disk cache and
response shape.

## Basic Usage

**Kotlin** — via the singleton (recommended; auto-downloads the bundle):

```kotlin
// build.gradle.kts: implementation(files("libs/TheStageCore.aar"))
import ai.thestage.qlip.TheStageAI

// Inside a coroutine (initialize / start_model / infer are suspend).
TheStageAI.registerContext(context)
TheStageAI.initialize(api_token = "your-api-token")

TheStageAI.start_model(
    model_name = "tts",
    engines_path = "TheStageAI/neutts-multilingual",
    config = mapOf("voice_id" to "paul", "language" to "english")
)

val json = TheStageAI.infer(
    model_name = "tts",
    input_json = mapOf("text" to "Hello, world!")
)
// Batch audio arrives as List<Double>: 24 kHz mono PCM.
val audio = (json[0]["audio"] as List<Double>)
    .map { it.toFloat() }.toFloatArray()
val sampleRate = json[0]["sample_rate"] as Int              // 24000
```

The direct Kotlin pipelines load from a **local** (already-downloaded)
engines directory — they do not download, so `prefetch_model` first:

```kotlin
import ai.thestage.qlip.models.neutts.NeuTTSMultilingual
import ai.thestage.qlip.models.neutts.NeuTTS

val dir = TheStageAI.prefetch_model(repo_id = "TheStageAI/neutts-multilingual")

val tts = NeuTTSMultilingual(
    engines_path = dir,
    voice_id = "paul",
    language = "english"
)

val result = tts.generate(text = "Hello, world!")
val audio = result.audio              // FloatArray, 24 kHz mono
val sample_rate = result.sample_rate  // 24000
```

The English-only nano variant follows the same shape:

```kotlin
val nanoDir = TheStageAI.prefetch_model(repo_id = "TheStageAI/neutts")
val nano = NeuTTS(engines_path = nanoDir, voice_id = "dave")
```

**Flutter** — JSON path:

```dart
import 'package:thestage_android_sdk/thestage_android_sdk.dart';
import 'dart:typed_data';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');

await TheStageFlutterSDK.start_model(
  model_name: 'tts',
  engines_path: 'TheStageAI/neutts-multilingual',
  config: {'voice_id': 'paul', 'language': 'english'},
);

final result = await TheStageFlutterSDK.infer(
  model_name: 'tts',
  input_json: {'text': 'Hello, world!'},
);
// Batch audio arrives as List<double>: 24 kHz mono PCM.
final audio = Float32List.fromList(
    (result[0]['audio'] as List).cast<double>());
final sampleRate = result[0]['sample_rate'] as int; // 24000
```

## Inputs / Outputs

| Direction | Type | Description |
|---|---|---|
| input  `text` | `String` | Text to synthesize. |
| input  `seed` | `Long?` | Deterministic sampling. |
| output `NeuTTSResult.audio` | `FloatArray` | 24 kHz mono PCM, samples in `[-1.0, 1.0]`. |
| output `NeuTTSResult.sample_rate` | `Int` | Always `24000`. |
| output `NeuTTSResult.audio_duration` | `Double` | Seconds of audio. |
| output `NeuTTSResult.rtf` | `Double` | Real-time factor (duration / wall time). |
| output `NeuTTSResult.tokens_per_second` | `Double` | Decode speed. |

## Streaming

`open_tts_streamer` is push-based: collect `streamer.output`
**concurrently** with `streamer.send(...)` so audio plays the moment
each sentence is ready. Typical use case is piping LLM tokens straight
into TTS.

**Kotlin:**

```kotlin
val streamer = TheStageAI.open_tts_streamer(model_name = "tts")

val consumer = launch {
    streamer.output.collect { chunk ->
        val pcm = chunk.audio
        if (pcm != null) player.enqueue(pcm)
    }
}

streamer.send("Hello, world. ")
streamer.send("This sentence streams as it synthesizes.")
streamer.finish()   // flush remaining buffer + close `output`
consumer.join()
```

A `NeuTTSMultilingual` or `NeuTTS` you construct yourself opens the
same streamer with `tts.open_tts_streamer()`. If you already have the
full text up-front, `TheStageAI.infer_stream(model_name = "tts",
input_json = mapOf("text" to text))` (or `tts.synthesize_stream(text
= text)` on a direct pipeline) does the same thing in a single call.
Use `streamer.cancel()` instead of
`finish()` to abort an in-flight turn (e.g. on barge-in) — that drops
the buffer and closes immediately.

**Flutter** — push-based streaming uses
`infer_stream` + `send` + `finish_stream` against a stable
`stream_id`. Open the stream with `stream_mode: 'push'` first, then
push sentences as they become available:

```dart
const streamId = 'tts-utterance-1';
final player = TSAudioPlayer(sampleRate: 24000)..start();

// 1) Open the stream + start consuming chunks concurrently.
final consumer = () async {
  final stream = TheStageFlutterSDK.infer_stream(
    model_name: 'tts',
    input_json: {'stream_mode': 'push'},  // wait for `send`
    stream_id: streamId,
  );
  await for (final chunk in stream) {
    final audio = chunk['audio'] as Float32List?;
    if (audio != null && audio.isNotEmpty) player.enqueue(audio);
    if (chunk['is_final'] == true) break;
  }
}();

// 2) Push sentences (e.g. from an LLM token stream).
await TheStageFlutterSDK.send(stream_id: streamId, text: 'Hello, world. ');
await TheStageFlutterSDK.send(
  stream_id: streamId,
  text: 'This sentence streams as it synthesizes.',
);

// 3) Signal end-of-input → flush remaining buffer, close the stream.
await TheStageFlutterSDK.finish_stream(stream_id: streamId);
await consumer;
```

For an already-known string, just call `infer_stream` with the full
`text` and skip `send` / `finish_stream`.

## Streaming Hyperparameters

`NeuTTSStreamConfig` controls codec-side audio chunking and crossfading.
Defaults match what the SDK ships with — only override these when you
need to trade latency against smoothness.

| Field | Default | Description |
|---|---|---|
| `chunk_frames_schedule` | `[8, 12, 20]` | Frames in the first chunks: small ones give a fast first audio, then every chunk has `frames_per_chunk`. An empty list turns the ramp off. **Passing `frames_per_chunk` or `first_frames_per_chunk` without a schedule turns it off too.** |
| `frames_per_chunk` | `25` | Chunk size after the schedule. Larger = fewer, longer chunks. |
| `first_frames_per_chunk` | `25` | Frames in the first chunk when there is no schedule (`null` = `frames_per_chunk`). |
| `lookforward` | `5` | Future frames decoded together with each chunk to stabilise the seam (overlap-add window). |
| `lookback` | `50` | Past frames re-decoded for context when bridging chunks; reduces audible boundaries. |
| `overlap_frames` | `1` | Frames of crossfade between consecutive chunks. |
| `realtime_gate` | `true` | Paces streaming synthesis toward real-time to keep NPU heat/power down; `false` synthesizes as fast as possible. |
| `realtime_lead_ms` | `2000` | Audio the pacing keeps buffered ahead of real-time, in ms. |
| `output_sample_rate` | `0` | Resample output to this rate in Hz; `0` keeps the native 24 kHz. |
| `chained_chunks` | model default | Keep decoder state continuous across a request's chunks for smoother joins. |

Generation knobs (`temperature`, `top_k`, …) live on
`TTSGenerationConfig` and are independent of these.

**Kotlin** — pass `stream_config` to `open_tts_streamer`, or `config`
to a direct pipeline's `synthesize_stream`:

```kotlin
import ai.thestage.qlip.models.neutts.NeuTTSStreamConfig

val streamer = tts.open_tts_streamer(
    stream_config = NeuTTSStreamConfig(
        chunk_frames_schedule = listOf(8, 12, 20),  // the default ramp
        frames_per_chunk = 25,
        lookforward = 5,
        lookback = 50,
        overlap_frames = 1
    )
)

val stream = tts.synthesize_stream(
    text = "Hello, world.",
    // an even smaller first chunk: faster first audio
    config = NeuTTSStreamConfig(chunk_frames_schedule = listOf(6, 12, 20))
)
```

The same knobs are exposed through the singleton:

```kotlin
val streamer = TheStageAI.open_tts_streamer(
    model_name = "tts",
    stream_config = NeuTTSStreamConfig(chunk_frames_schedule = listOf(6, 12, 20))
)
```

**Flutter** (and the Kotlin JSON path) — put the fields at the top
level of `input_json`, next to `text`:

```dart
final stream = TheStageFlutterSDK.infer_stream(
  model_name: 'tts',
  input_json: {
    'text': 'Hello, world.',
    'chunk_frames_schedule': [8, 12, 20],   // the default ramp
    'frames_per_chunk': 25,
    'lookforward': 5,
    'lookback': 50,
    'overlap_frames': 1,
  },
);
```

Unknown keys are ignored; defaults are kept for any field you omit.

## Voices and Languages

Voices live under `voices/{voice_id}/` inside the bundle. The
multilingual model supports:

`english`, `french`, `german`, `spanish`, `portuguese`, `japanese`,
`korean`, `chinese`, `urdu`

Pass the language at construction time; left unset, it defaults to
the voice's own language. The English-only `TheStageAI/neutts`
bundle ignores it.

Three knobs pick what the model speaks with:

- **`voice_id`** picks a voice that ships in the bundle (the `voices`
  list in the `start_model` result). Empty = the bundle's first voice.
- **`voice_dir`** points at a voice pack: **one folder holding a
  `voice.json`** (yours, or a downloaded one). It wins over
  `voice_id`. An empty value is ignored.
- **`language`** switches the language while keeping the speaker.

**Flutter** — pick the voice at load. A request can also carry
`voice_id` (and, on the multilingual bundles, `language`) in
`input_json` to speak that one request with another voice. To change
`voice_dir`, stop and start again:

```dart
await TheStageFlutterSDK.stop_model(model_name: 'tts');
await TheStageFlutterSDK.start_model(
  model_name: 'tts',
  engines_path: 'TheStageAI/neutts-multilingual',
  config: {
    'voice_id': 'dave',
    'language': 'french',
    // 'voice_dir': '/path/to/your/voice_pack',   // wins over voice_id
  },
);
```

**Kotlin** — the same keys work in `TheStageAI.start_model(config =
...)`. A `NeuTTSMultilingual` you construct yourself also switches at
runtime with `set_voice`, without reloading the LLM or codec (a voice
is only reference codes and text). `null` keeps a value; an empty
`voice_dir` returns to the bundle voice; an empty `language` returns
to the voice's own language. An unknown `voice_id` or language, or a
`voice_dir` without `voice.json`, throws and keeps the current voice.
Call it between utterances.

```kotlin
val tts = NeuTTSMultilingual(
    engines_path = dir,
    voice_id = "paul",
    language = "english",
    // voice_dir = packDir.path,              // wins over voice_id
)
tts.set_voice(voice_id = "dave")
tts.set_voice(voice_id = "dave", language = "french")
tts.set_voice(voice_dir = packDir.path)       // your own voice pack
tts.set_voice(voice_dir = "")                 // back to "dave"
```

**Your own voice.** A voice pack is a folder with one `voice.json`,
made offline from a short reference clip (3–10 s) and its transcript;
see [`voice.json` shape](#voicejson-shape). Packs work on the
multilingual NeuTTS bundles. Copy the folder to a real path on the
device (download it, or extract it from your assets) and pass that
path. A `voice_dir` without a `voice.json` fails the load (or the
`set_voice` call, keeping the current voice), and so does any
`voice_dir` on the English-only nano bundle, whose voices use a
different format.

> Inside the Voice Agent the same knobs are `tts_voice`,
> `tts_voice_dir` and `tts_language` in the config, and
> `agent.set_voice(...)` at runtime — see [Voice Agent](./voice_agent.md#voices).

## Custom Voices

Beyond the voices baked into a bundle, an app can supply its own. Each
custom voice is a folder with a single `voice.json`; the SDK merges
them with the bundle's built-in voices, so they show up in the
`voices` list returned by `start_model` and are selectable by
`voice_id` exactly like the built-ins.

Custom voices ship as **assets inside your app**. The
`custom_voices_assets` config key is the **name of the asset folder**
that holds them; the SDK extracts that folder out of the APK on load
and merges the voices in. Inside it, each voice is its own subfolder
with a single `voice.json`:

```
neutts_voices/
  my_voice/
    voice.json
```

Where that folder lives depends on the app type. Pass the **same
folder name** (`neutts_voices`) either way — the SDK looks in both
locations, so one config value serves a Flutter app, a native app,
or one that carries both:

| App | Put the folder at |
|---|---|
| **Flutter** | `assets/<folder>/` in your project, declared under `flutter: assets:` in `pubspec.yaml` |
| **Native Android** | `src/main/assets/<folder>/` |

**Flutter** — declare each voice file in `pubspec.yaml`, then pass the
folder name:

```yaml
flutter:
  assets:
    - assets/neutts_voices/my_voice/voice.json
```

```dart
await TheStageFlutterSDK.start_model(
  model_name: 'tts',
  engines_path: 'TheStageAI/neutts-multilingual',
  config: {
    'voice_id': 'my_voice',
    'language': 'english',
    'custom_voices_assets': 'neutts_voices',
  },
);
```

**Native Android (Kotlin)** — drop the folder at
`src/main/assets/neutts_voices/` and pass its name:

```kotlin
TheStageAI.start_model(
    model_name = "tts",
    engines_path = "TheStageAI/neutts-multilingual",
    config = mapOf(
        "voice_id" to "my_voice",
        "language" to "english",
        "custom_voices_assets" to "neutts_voices",
    )
)
```

### `voice.json` shape

A `voice.json` is small (~4 KB) — reference text, the codec codes for
that reference audio, and per-voice generation defaults:

```json
{
  "name": "my_voice",
  "language": "english",
  "ref_text": "A short sentence spoken in the reference clip.",
  "ref_codes": [ [ 1234, 5678, ... ] ],
  "temperature": 0.7,
  "top_k": 50,
  "max_length": 1024,
  "use_lang_token": true
}
```

| Field | Required | Description |
|---|---|---|
| `name` | yes | Display name; usually matches the folder. |
| `language` | yes | One of the supported languages. |
| `ref_text` | yes | Transcript of the reference audio the codes came from. |
| `ref_codes` | yes | NeuCodec codes for the reference audio (authored offline). |
| `temperature`, `top_k`, `max_length`, `min_new_tokens`, `use_lang_token` | no | Per-voice generation defaults; omit to use the model defaults. |

> **`ref_codes` are authored offline.** The on-device SDK ships the
> NeuCodec **decoder** only, so it cannot turn a reference `.wav` into
> codes on the phone. Produce the codes ahead of time with the NeuCodec
> encoder and paste them into `voice.json`.

To ship a voice with your app, drop its `voice.json` under your asset
folder (see the table above for where that folder lives), point
`custom_voices_assets` at that folder, and it appears in the `voices`
list at load.

## Audio Output

- 24 kHz mono `FloatArray`, samples in `[-1.0, 1.0]`.
- **Batch:** `NeuTTSResult.audio` is the full utterance.
- **Streaming:** each `InferenceStreamChunk.audio` is one
  sentence-sized PCM slice; `chunk.sample_rate` is `24000`. The
  streamer applies overlap-add crossfading between sentences, so
  consumers can concatenate slices end-to-end.
- If your playback path runs at 16 kHz to match VAD/ASR, set
  `output_sample_rate: 16000` to have the SDK resample for you, resample
  the output yourself, or drive your `TSAudioPlayer` at 24 kHz
  (the bundled player defaults to 24 kHz).

See [Audio I/O Contract](./README.md#audio-io-contract) for the
shared format used across VAD / ASR / TTS.

## Singleton API (`TheStageAI`)

`TheStageAI` is a Kotlin `object` (singleton); its methods are
`suspend`.

```kotlin
TheStageAI.start_model(
    model_name = "tts",
    engines_path = "TheStageAI/neutts-multilingual",
    config = mapOf("voice_id" to "paul", "language" to "english")
)

val json = TheStageAI.infer(
    model_name = "tts",
    input_json = mapOf(
        "text" to "Hello, world!",
        "seed" to 42L                  // optional
    )
)
val audio = json[0]["audio"]
```

JSON response keys: `audio`, `sample_rate` (`Int`), `duration`
(`Double`), `tokens_per_second` (`Double`), `rtf` (`Double`),
plus per-stage timings.

JSON streaming yields typed `InferenceStreamChunk` values; PCM samples
live on `chunk.audio`:

```kotlin
TheStageAI.infer_stream(
    model_name = "tts",
    input_json = mapOf("text" to "A long paragraph of text to speak.")
).collect { chunk ->
    val audio = chunk.audio
    if (audio != null && audio.isNotEmpty()) {
        play(audio, chunk.sample_rate ?: 24000)
    }
    if (chunk.is_final) return@collect
}
```

A push-based streamer is also reachable via the singleton:

```kotlin
val streamer = TheStageAI.open_tts_streamer(model_name = "tts")
// streamer.send(...) / streamer.finish() / streamer.cancel(),
// audio on streamer.output — see Streaming above
```

The Flutter `TheStageFlutterSDK.infer` / `infer_stream` calls hit this
exact JSON path, so the response keys above apply unchanged on Dart.
Streaming chunks carry their PCM as `Float32List`; do not promote it
to `Float64List`. Batch `infer` returns `audio` as `List<double>`;
convert it with `Float32List.fromList(...cast<double>())`.

## Full Constructor

```kotlin
val tts = NeuTTSMultilingual(
    engines_path = dir,               // local (prefetched) dir
    voice_id = "paul",                // voice subfolder under voices/
    language = "english",             // optional language override
    voice_dir = null,                 // optional voice-pack folder
)

val nano = NeuTTS(
    engines_path = nanoDir,
    voice_id = "dave"
)
```

Per-component device placement (LLM on NPU, NeuCodec pre/post on CPU)
is set in the bundle's `metadata.json`. Through the singleton,
`start_model(device = ...)` chooses which bundle to download (see
[Choosing the device](./model_management.md#choosing-the-device)) and
`devices = ...` overrides the placement of individual modules.
`TheStageAI.initialize(...)` must have succeeded before either call.

## Load Progress

Download / extract / load progress is reported through the singleton
and Flutter entry points via an optional `on_load_progress`
handler. `phase` is the signal; `fraction` is non-null only
while downloading, where it runs `0.0 .. 1.0`:

```kotlin
TheStageAI.start_model(
    model_name = "tts",
    engines_path = "TheStageAI/neutts-multilingual",
    config = mapOf("voice_id" to "paul"),
    on_load_progress = { p ->
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
  if (event['model_name'] != 'tts') return;
  // phase: downloading | waiting_for_wifi |
  //        waiting_for_confirmation | extracting | loading | ready
  final phase    = event['phase']    as String?;
  // Present only while downloading. Null => show an
  // indeterminate indicator; do NOT fall back to 0.
  final fraction = event['progress'] as num?;
  final pct = fraction == null
      ? ''
      : ' ${(fraction * 100).toStringAsFixed(0)}%';
  print('[tts] $phase$pct');
});

await TheStageFlutterSDK.start_model(
  model_name: 'tts',
  engines_path: 'TheStageAI/neutts-multilingual',
  config: {'voice_id': 'paul', 'language': 'english'},
);
```

## Prefetch Engines

```kotlin
val engines_dir = TheStageAI.prefetch_model(
    repo_id = "TheStageAI/neutts-multilingual"
)

// Later — instant load, no network:
val tts = NeuTTSMultilingual(
    engines_path = engines_dir,
    voice_id = "paul"
)
```

## Cleanup

The direct pipelines expose `close()` to release them. When you used
the singleton API:

```kotlin
TheStageAI.stop_model(model_name = "tts")
```

**Flutter:**

```dart
await TheStageFlutterSDK.stop_model(model_name: 'tts');
```

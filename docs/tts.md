# NeuTTS (Text-to-Speech)

On-device neural text-to-speech with batch and push-based streaming.
Two public pipelines:

- **`NeuTTSMultilingual`** — Qwen3-based, 9 languages.
- **`NeuTTS`** (nano) — phoneme-based, English only, faster.

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
val audio       = json[0]["audio"]                          // 24 kHz mono PCM
val sampleRate  = json[0]["sample_rate"] as Int             // 24000
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
final audio       = result[0]['audio']       as Float32List;
final sampleRate  = result[0]['sample_rate'] as int; // 24000
```

## Inputs / Outputs

| Direction | Type | Description |
|---|---|---|
| input  `text` | `String` | Text to synthesize. |
| input  `config.seed` | `Long?` | Deterministic sampling. |
| output `NeuTTSResult.audio` | `FloatArray` | 24 kHz mono PCM, samples in `[-1.0, 1.0]`. |
| output `NeuTTSResult.sample_rate` | `Int` | Always `24000`. |
| output `NeuTTSResult.audio_duration` | `Double` | Seconds of audio. |
| output `NeuTTSResult.rtf` | `Double` | Real-time factor (duration / wall time). |
| output `NeuTTSResult.tokens_per_second` | `Double` | Decode speed. |

## Streaming

`open_streamer` is push-based: collect `streamer.output` **concurrently**
with `streamer.send(...)` so audio plays the moment each sentence is
ready. Typical use case is piping LLM tokens straight into TTS.

**Kotlin:**

```kotlin
val streamer = tts.open_streamer()

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

If you already have the full text up-front, `infer_stream(text)` does
the same thing in a single call. Use `streamer.cancel()` instead of
`finish()` to abort an in-flight turn (e.g. on barge-in) — that drops
the buffer and closes immediately.

**Flutter** — push-based streaming uses
`infer_stream` + `send` + `finish_stream` against a stable
`stream_id`. Open the stream with empty text first, then push
sentences as they become available:

```dart
const streamId = 'tts-utterance-1';
final player = TheStageAudioPlayer(sampleRate: 24000)..start();

// 1) Open the stream + start consuming chunks concurrently.
final consumer = () async {
  final stream = TheStageFlutterSDK.infer_stream(
    model_name: 'tts',
    input_json: {'text': ''},   // empty = wait for `send`
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
| `frames_per_chunk` | `25` | Codec frames decoded per emitted audio chunk after the first. Larger = fewer, longer chunks. |
| `first_frames_per_chunk` | `25` | Frames in the **first** chunk; pass a smaller value (or `null` to fall back to `frames_per_chunk`) to lower time-to-first-audio. |
| `lookforward` | `5` | Future frames decoded together with each chunk to stabilise the seam (overlap-add window). |
| `lookback` | `50` | Past frames re-decoded for context when bridging chunks; reduces audible boundaries. |
| `overlap_frames` | `1` | Frames of crossfade between consecutive chunks. |
| `realtime_gate` | `true` | Paces streaming synthesis toward real-time to keep NPU heat/power down; `false` synthesizes as fast as possible. |
| `output_sample_rate` | `0` | Resample output to this rate in Hz; `0` keeps the native 24 kHz. |
| `chained_chunks` | model default | Keep decoder state continuous across a request's chunks for smoother joins. |

Generation knobs (`temperature`, `top_k`, …) live on
`TTSGenerationConfig` and are independent of these.

**Kotlin** — pass `stream_config:` to `open_streamer` or `infer_stream`:

```kotlin
val streamer = tts.open_streamer(
    stream_config = NeuTTSStreamConfig(
        frames_per_chunk = 25,
        first_frames_per_chunk = 12,   // smaller first chunk → faster first audio
        lookforward = 5,
        lookback = 50,
        overlap_frames = 1
    )
)

val stream = tts.infer_stream(
    text = "Hello, world.",
    stream_config = NeuTTSStreamConfig(first_frames_per_chunk = 12)
)
```

The same knobs are exposed through the singleton:

```kotlin
val streamer = TheStageAI.open_tts_streamer(
    model_name = "tts",
    stream_config = NeuTTSStreamConfig(first_frames_per_chunk = 12)
)
```

**Flutter** — drop a `stream_config` map into `input_json`:

```dart
final stream = TheStageFlutterSDK.infer_stream(
  model_name: 'tts',
  input_json: {
    'text': 'Hello, world.',
    'stream_config': {
      'frames_per_chunk': 25,
      'first_frames_per_chunk': 12,
      'lookforward': 5,
      'lookback': 50,
      'overlap_frames': 1,
    },
  },
);
```

Unknown keys are ignored; defaults are kept for any field you omit.

## Voices and Languages

Voices live under `voices/{voice_id}/` inside the bundle. The
multilingual model supports:

`english`, `french`, `german`, `spanish`, `portuguese`, `japanese`,
`korean`, `chinese`, `urdu`

Pass the language at construction time (it can be overridden per-voice
default). The nano variant is English-only and ignores the parameter.

## Audio Output

- 24 kHz mono `FloatArray`, samples in `[-1.0, 1.0]`.
- **Batch:** `NeuTTSResult.audio` is the full utterance.
- **Streaming:** each `InferenceStreamChunk.audio` is one
  sentence-sized PCM slice; `chunk.sample_rate` is `24000`. The
  streamer applies overlap-add crossfading between sentences, so
  consumers can concatenate slices end-to-end.
- If your playback path runs at 16 kHz to match VAD/ASR, set
  `output_sample_rate: 16000` to have the SDK resample for you, resample
  the output yourself, or drive your `TheStageAudioPlayer` at 24 kHz
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
// same `streamer.send(...)` / `streamer.finish()` shape as above
```

The Flutter `TheStageFlutterSDK.infer` / `infer_stream` calls hit this
exact JSON path, so the response keys above apply unchanged on Dart.
PCM audio crosses the platform channel as `Float32List`; do not
promote to `Float64List`.

## Full Constructor

```kotlin
val tts = NeuTTSMultilingual(
    engines_path = dir,               // local (prefetched) dir
    voice_id = "paul",                // voice subfolder under voices/
    language = "english"              // optional language override
)

val nano = NeuTTS(
    engines_path = nanoDir,
    voice_id = "dave"
)
```

Per-component device placement (LLM on NPU, NeuCodec pre/post on CPU)
is set in the bundle's `metadata.json`; when downloading through the
singleton, pass overrides via `start_model(device = ..., devices = ...)`.
`TheStageAI.initialize(...)` must have succeeded before either call.

## Load Progress

Download / extract / load progress is reported through the singleton
and Flutter entry points via an optional `on_load_progress` handler
that fires through four phases with a monotonic `fraction` in
`0.0 .. 1.0`:

```kotlin
TheStageAI.start_model(
    model_name = "tts",
    engines_path = "TheStageAI/neutts-multilingual",
    config = mapOf("voice_id" to "paul"),
    on_load_progress = { p ->
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
  if (event['model_name'] != 'tts') return;
  final phase    = event['phase']    as String?;   // downloading | extracting | loading | ready
  final fraction = event['progress'] as double?;   // 0.0 ... 1.0, monotonic
  print('[tts] $phase ${(fraction ?? 0) * 100}%');
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

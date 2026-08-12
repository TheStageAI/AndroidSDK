# Streaming

Real-time streaming inference for TTS, LLM, and ASR pipelines.

---

## TTS Streaming

Yields audio chunks as sentences are synthesized — much lower time-to-first-audio than batch mode.

### Kotlin — Simple Consumer

```kotlin
// build.gradle.kts: implementation(files("libs/TheStageCore.aar"))
import ai.thestage.qlip.TheStageAI

// Inside a coroutine.
TheStageAI.registerContext(context)
TheStageAI.initialize(api_token = "your_api_token")

TheStageAI.start_model(
    model_name = "tts",
    engines_path = "TheStageAI/neutts-multilingual",
    config = mapOf("voice_id" to "dave"),
    revision = "android"
)

TheStageAI.infer_stream(
    model_name = "tts",
    input_json = mapOf("text" to "A long paragraph of text to speak aloud.")
).collect { chunk ->
    val audio = chunk.audio ?: return@collect
    play_audio(audio, chunk.sample_rate ?: 24000)

    if (chunk.is_final) {
        println("Decode tokens: ${chunk.generated_tokens ?: 0}")
        println("Tok/s: ${chunk.tokens_per_second ?: 0.0}")
        println("First chunk: ${chunk.time_to_first_token ?: 0.0}s")
        println("Total wall-clock: ${chunk.total_seconds ?: 0.0}s")
    }
}
```

### Kotlin — Producer / Consumer with AudioStreamPlayer

Two concurrent coroutines: one drives TTS inference, the other plays
audio as chunks arrive. This is the recommended pattern for low-latency
playback.

```kotlin
import ai.thestage.qlip.audio.AudioStreamPlayer
import ai.thestage.qlip.audio.AudioStreamConfig

TheStageAI.start_model(
    model_name = "tts",
    engines_path = "TheStageAI/neutts-multilingual",
    config = mapOf("voice_id" to "paul")
)

val player = AudioStreamPlayer(
    AudioStreamConfig(
        sample_rate = 24000,
        channels = 1,
        queue_capacity = 256
    )
)
player.start()

TheStageAI.infer_stream(
    model_name = "tts",
    input_json = mapOf("text" to "Hello! This is a streaming demo with real-time audio.")
).collect { chunk ->
    val audio = chunk.audio
    if (audio != null && audio.isNotEmpty()) player.enqueue(audio)
}

player.drain()
player.stop()
```

### AudioStreamConfig Options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `sample_rate` | `Int` | 24000 | Audio sample rate in Hz |
| `channels` | `Int` | 1 | Number of audio channels |
| `queue_capacity` | `Int` | 256 | Bounded PCM queue depth feeding the writer thread |
| `voice_processing` | `Boolean` | false | Route playback as voice communication so the platform `AcousticEchoCanceler` references it (required for AEC); media routing otherwise |

The player is backed by an Android `AudioTrack` in `MODE_STREAM`;
`enqueue` is non-blocking and `drain()` (suspend) waits until
everything queued and buffered has actually played out.

### Kotlin — Push-Based (LLM → TTS)

Feed text incrementally as it arrives from another model. The streamer
splits sentences internally and produces audio as complete sentences are
ready. Use `TheStageAI.open_tts_streamer(model_name)` to pull a fresh
streamer per turn — there is no need (or way) to construct `TTSStreamer`
directly from outside the SDK module.

```kotlin
TheStageAI.start_model(
    model_name = "llm",
    engines_path = "TheStageAI/Qwen3-0.6B"
)
TheStageAI.start_model(
    model_name = "tts",
    engines_path = "TheStageAI/neutts-multilingual",
    config = mapOf("voice_id" to "dave")
)

val player = AudioStreamPlayer(sample_rate = 24000)
player.start()

val streamer = TheStageAI.open_tts_streamer(model_name = "tts")

// Audio consumer coroutine
val consumer = launch {
    streamer.output.collect { chunk ->
        val pcm = chunk.audio
        if (pcm != null && pcm.isNotEmpty()) player.enqueue(pcm)
    }
    player.drain()
    player.stop()
}

// LLM → TTS producer
TheStageAI.infer_stream(
    model_name = "llm",
    input_json = mapOf("prompt" to "Tell me a joke", "max_new_tokens" to 256)
).collect { chunk ->
    val delta = chunk.delta
    if (delta != null && delta.isNotEmpty()) streamer.send(delta)
    if (chunk.is_final) streamer.finish()   // flush tail + close output cleanly
}
```

`streamer.finish()` flushes any partial sentence buffered inside the
splitter before closing the output flow. Use `streamer.cancel()`
instead if you want to abort an in-flight turn (e.g. on barge-in) —
that drops the buffer and closes immediately.

This is exactly what `TheStageVoiceAgent` does internally: its TTS node
opens one push-based `TTSStreamer` per turn, pumps LLM deltas straight
in, and `cancel()`s on barge-in.

---

## Flutter — TTS Streaming

### Simple Usage

```dart
final stream = TheStageFlutterSDK.infer_stream(
  model_name: 'tts',
  input_json: {'text': 'A long paragraph of text to speak aloud.'},
);

final player = TheStageAudioPlayer(sampleRate: 24000);
await player.start();

await for (final chunk in stream) {
  final audio = chunk['audio'] as Float32List?;
  if (audio != null && audio.isNotEmpty) {
    player.enqueue(audio);
  }
  if (chunk['is_final'] == true) break;
}

await player.drain();
await player.stop();
```

### Push-Based (LLM → TTS)

```dart
final ttsStream = TheStageFlutterSDK.infer_stream(
  model_name: 'tts',
  input_json: {'text': ''},
  stream_id: 'voice_agent_tts',
);

final player = TheStageAudioPlayer(sampleRate: 24000);
await player.start();

ttsStream.listen((chunk) {
  final audio = chunk['audio'] as Float32List?;
  if (audio != null) player.enqueue(audio);
});

final llmStream = TheStageFlutterSDK.infer_stream(
  model_name: 'llm',
  input_json: {
    'prompt': 'Tell me a joke',
    'max_new_tokens': 256,
  },
);

await for (final chunk in llmStream) {
  if (chunk['kind'] == 'text' && chunk['delta'] != null) {
    await TheStageFlutterSDK.send(
      stream_id: 'voice_agent_tts',
      text: chunk['delta'],
    );
  }
  if (chunk['is_final'] == true) {
    await TheStageFlutterSDK.finish_stream(stream_id: 'voice_agent_tts');
  }
}

await player.drain();
await player.stop();
```

---

## Streaming ASR (Speech-to-Text)

The inverse direction — push microphone audio in, read transcripts out
— is available on Android through the **Voice Agent**
([voice_agent.md](./voice_agent.md)), which runs streaming ASR
internally. Its ASR node re-decodes the growing turn buffer on a single
serial worker and commits stable text via LocalAgreement, so partials
grow monotonically and never flicker, while the authoritative
end-of-turn transcript always covers the complete utterance (including
the last word).

For a standalone, reusable streamer outside the voice agent, open one on
a loaded Whisper model from Kotlin (mirrors `open_tts_streamer`):

```kotlin
val asr = TheStageAI.open_asr_streamer(
    model_name = "stt", language = "en",
)
scope.launch { asr.partials.collect { caption -> /* live text */ } }
for (chunk in micStream) asr.send(chunk)   // 16 kHz mono FloatArray
val finalText = asr.finish()               // authoritative transcript
```

It re-decodes the growing buffer on a single serial worker and commits
stable text via the same LocalAgreement-2 as the voice agent, so
`partials` grow monotonically. This is a native-Kotlin API — there is no
plugin/Dart channel route for it; from Flutter, drive
`TheStageVoiceAgent` for live speech-to-text or use the batch `infer` for
one-shot transcription (see [whisper.md](./whisper.md)). Convert mic
input to 16 kHz mono Float first — it is **not** resampled.

---

## Stream Chunk Format

For the SDK-wide audio format contract (sample rates, mono Float, frame
sizes for VAD vs ASR vs TTS) see [Audio I/O Contract](./README.md#audio-io-contract).

### TTS Chunks

| Field | Type | Description |
|-------|------|-------------|
| `audio` | `FloatArray` / `Float32List` | PCM audio samples, 24 kHz mono, normalized to `[-1.0, 1.0]` |
| `sample_rate` | `Int` | Always 24000 |
| `index` | `Int` | Sequential chunk number |
| `is_final` | `Boolean` | `true` on the sentinel (empty) last chunk |
| `time_to_first_token` | `Double?` | Seconds to first audio chunk |
| `generated_tokens` | `Int?` | Decode step count (excludes prefill) |
| `tokens_per_second` | `Double?` | Decode speed: `steps / sum_of_step_durations` (measured inside decoder) |
| `total_seconds` | `Double?` | Wall-clock time from stream start to last chunk (final only) |

### LLM Chunks

| Field | Type | Description |
|-------|------|-------------|
| `delta` (Kotlin & Flutter) | `String?` | Decoded token text (null on the final sentinel) |
| `index` | `Int` | Position in sequence |
| `is_final` | `Boolean` | `true` for the sentinel chunk |
| `time_to_first_token` | `Double?` | Seconds to first token (final only) |
| `prompt_tokens` | `Int?` | Input token count (final only) |
| `generated_tokens` | `Int?` | Output token count (final only) |
| `tokens_per_second` | `Double?` | Generation speed (final only) |
| `total_seconds` | `Double?` | Wall-clock time (final only) |

---

## Flutter API Reference

### Lifecycle

```dart
await TheStageFlutterSDK.initialize(api_token: 'your_token');

await TheStageFlutterSDK.start_model(
  model_name: 'tts',
  engines_path: 'TheStageAI/neutts-multilingual',
  model_type: 'neutts-multilingual',
  revision: 'android',
  config: {'voice_id': 'dave'},
);

await TheStageFlutterSDK.stop_model(model_name: 'tts');
```

### Streaming

```dart
final stream = TheStageFlutterSDK.infer_stream(
  model_name: 'tts',
  input_json: {'text': 'Hello world.'},
);

await TheStageFlutterSDK.send(stream_id: id, text: 'more text');
await TheStageFlutterSDK.finish_stream(stream_id: id);
await TheStageFlutterSDK.stop_stream(stream_id: id);
```

### Audio Player

```dart
final player = TheStageAudioPlayer(sampleRate: 24000);
await player.start();
player.enqueue(audioData);
await player.pause();
await player.resume();
await player.drain();
await player.stop();
```

---

## Cancellation

Cancel any active stream at any time:

```kotlin
// Kotlin — cancel the collecting coroutine, or call streamer.cancel()
```

```dart
// Flutter
await TheStageFlutterSDK.stop_stream(stream_id: 'my_stream');
```

The stream will emit a final event with `kind: 'cancelled'` and close.

---

## Architecture

### TTSStreamer — Single Token Stream with Sentinels

```
Producer Task                          Consumer Task
─────────────                          ─────────────
sentence_stream                        token_stream
    │                                      │
    ▼                                      ▼
┌──────────┐                         ┌───────────┐
│preprocess│                         │is sentinel?│
└────┬─────┘                         └─┬───────┬─┘
     │                                 no      yes
     ▼                                 │        │
┌──────────────┐                       ▼        ▼
│decoder       │                  accumulate   flush
│  .prefill()  │                  codes        + fade-out
│  .decode_step│                       │        + reset
│  (loop)      │                       ▼
└────┬─────────┘                  ┌─────────┐
     │                            │codec.infer│
     ▼                            │           │
yield tokens                      └────┬────┘
     │                                 │
     ▼                                 ▼
yield sentinel                    OLA + emit
```

The producer runs ahead — while the consumer decodes audio for the
current sentence, the producer is already preprocessing and generating
tokens for the next one. This eliminates inter-sentence pauses.

---

## Engine Requirements

Streaming and batch inference use the same model bundle — no extra
setup. Just use `infer_stream` instead of `infer`, or pull a push-based
`TTSStreamer` via `TheStageAI.open_tts_streamer(...)`.

## Tuning the TTS Streamer

`NeuTTSStreamConfig` exposes the codec-side chunking knobs that decide
time-to-first-audio and how seams between sentences sound. Defaults
match what the SDK ships with — only override these when you need to
trade latency against smoothness.

**Kotlin:**

```kotlin
import ai.thestage.qlip.models.neutts.NeuTTSStreamConfig

val streamer = tts.open_streamer(
    stream_config = NeuTTSStreamConfig(
        frames_per_chunk = 25,
        first_frames_per_chunk = 12,   // smaller first chunk → faster first audio
        lookforward = 5,
        lookback = 50,
        overlap_frames = 1
    )
)

// Or via the singleton:
val s2 = TheStageAI.open_tts_streamer(
    model_name = "tts",
    stream_config = NeuTTSStreamConfig(first_frames_per_chunk = 12)
)
```

`infer_stream(text, stream_config)` accepts the same struct when you
already have the full text up front.

**Flutter** — pass a nested `stream_config` map inside `input_json`:

```dart
final stream = TheStageFlutterSDK.infer_stream(
  model_name: 'tts',
  input_json: {
    'text': 'Hello, world.',
    'stream_config': {
      'first_frames_per_chunk': 12,
      'frames_per_chunk': 25,
      'lookforward': 5,
      'lookback': 50,
      'overlap_frames': 1,
    },
  },
);
```

See [NeuTTS — Streaming Hyperparameters](./tts.md#streaming-hyperparameters)
for the full field reference.

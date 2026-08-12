# TheStage Android SDK — Documentation

On-device speech, language and audio inference for **Android** on
Qualcomm Snapdragon. The SDK runs compiled engines on the Hexagon NPU
(HTP, via the QNN runtime) with automatic **GPU / CPU fallback**, pulls
engines from HuggingFace on first use, and exposes a unified `infer` /
`infer_stream` API for every pipeline. No server in the hot path.

This folder is the customer-facing reference for both consumption
surfaces: the native **Kotlin** singleton (`TheStageAI`) and the
**Flutter** plugin (`thestage_android_sdk` → `TheStageFlutterSDK`).

## Table of Contents

- [LLM (Language Model)](./llm.md) — **(coming soon)** Qwen3 /
  LFM2.5 chat with streaming, KV cache, chat-template auto-detect.
- [Whisper ASR](./whisper.md) — speech-to-text with automatic VAD
  chunking and long-audio stitching.
- [VLM (Vision-Language)](./vlm.md) — on-device image + prompt → text
  (LFM2.5-VL), batch and streaming.
- [NeuTTS](./tts.md) — multilingual (9 languages) and nano (English)
  neural TTS with batch + push-based streaming.
- [VAD](./vad.md) — Silero VAD: stateful per-chunk speech detection.
- [Streaming](./streaming.md) — TTS / LLM streaming patterns,
  back-pressure, sentence segmentation, Flutter consumers.
- [Voice Agent](./voice_agent.md) — end-to-end voice assistant
  (VAD → STT → LLM → TTS) with neural end-of-turn detection and
  barge-in.
- [Model Management](./model_management.md) — availability probing,
  prefetch, per-component load/unload, bundled-engine paths, and
  process-memory reporting.
- [AI Packs](./ai_packs.md) — ship models via Google Play AI packs
  (`aipack://` engines source): pack modules, device targeting,
  delivery modes, availability.
- [Speaker Embedding](./speaker_embedding.md) — ReDimNet2 speaker-id:
  enroll + cosine verification, and voice-agent speaker gating.
- [Licensing & Device Identity](./licensing.md) — how `(apiToken,
  deviceId)` is derived on Android, what counts as a device, reinstall
  behavior, device-integrity enforcement, and online-validation behavior.
- [Product Terms](./product_terms.md) — commercial / licensing summary:
  seat model and pricing via Service Request (no public rate card).
- [Logging & Diagnostics](./logging.md) — the diagnostics ring, session
  log file, and the Flutter `logs` stream (no user content, sanitized
  paths).
- [Audio I/O Contract](#audio-io-contract) — sample rate, format and
  chunking expectations shared across VAD / ASR / TTS (read this
  before wiring up your mic / speaker stack).

## Quick Start

**Kotlin:**

```kotlin
import ai.thestage.qlip.TheStageAI

TheStageAI.registerContext(context)
TheStageAI.initialize(api_token = "your-api-token")

TheStageAI.start_model(
    model_name = "stt",
    engines_path = "TheStageAI/thewhisper-large-v3-turbo",
)

val result = TheStageAI.infer(
    model_name = "stt",
    input_json = mapOf(
        "audio" to pcm_16k_mono,   // FloatArray, mono, [-1, 1]
        "language" to "en",
    ),
)
println(result[0]["transcription"])
```

**Flutter:**

```dart
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');

// Subscribe to load progress for any model_name.
TheStageFlutterSDK.on_progress.listen((event) {
  if (event['model_name'] != 'stt') return;
  print('[stt] ${event['phase']} ${(event['progress'] as double) * 100}%');
});

await TheStageFlutterSDK.start_model(
  model_name: 'stt',
  engines_path: 'TheStageAI/thewhisper-large-v3-turbo',
);

final result = await TheStageFlutterSDK.infer(
  model_name: 'stt',
  input_json: {
    'audio': pcm_16k_mono,   // Float32List, mono, [-1, 1]
    'language': 'en',
  },
);
print(result[0]['transcription']);
```

## Kotlin ↔ Flutter Quick Reference

The Kotlin singleton (`TheStageAI`) and the Flutter
`TheStageFlutterSDK` mirror each other one-to-one. Dart consumers
always go through the JSON path.

| Operation | Kotlin | Flutter (Dart) |
|---|---|---|
| Initialize | `TheStageAI.registerContext(context)` then `TheStageAI.initialize(api_token = "...")` | `await TheStageFlutterSDK.initialize(api_token: '...')` |
| Start a model | `TheStageAI.start_model(model_name =, engines_path =, config =)` | `await TheStageFlutterSDK.start_model(model_name:, engines_path:, config:)` |
| Stop a model | `TheStageAI.stop_model(model_name = "llm")` | `await TheStageFlutterSDK.stop_model(model_name: 'llm')` |
| Single-shot inference | `TheStageAI.infer(model_name =, input_json =) -> List<Map<String, Any>>` | `await TheStageFlutterSDK.infer(model_name:, input_json:) -> List<Map<String, dynamic>>` |
| Streaming inference | `TheStageAI.infer_stream(model_name =, input_json =) -> Flow<Map<String, Any>>` | `TheStageFlutterSDK.infer_stream(model_name:, input_json:, stream_id:?) -> Stream<Map<String, dynamic>>` |
| Push text into a TTS stream | `TheStageAI.send(stream_id =, text =); TheStageAI.finish_stream(stream_id =)` | `await TheStageFlutterSDK.send(stream_id:, text:); await TheStageFlutterSDK.finish_stream(stream_id:)` |
| Cancel a running stream | `TheStageAI.stop_stream(stream_id =)` | `await TheStageFlutterSDK.stop_stream(stream_id:)` |
| Load progress | `config` progress callback / `on_progress` flow | Single global stream `TheStageFlutterSDK.on_progress` (`{model_name, phase, progress}`) |
| Audio buffer type | `FloatArray` | `Float32List` (never `Float64List`) |

## Load Progress

All loaders emit progress through four phases with a monotonic
fraction in `0…1`:

| Phase         | Fraction band   | Notes |
|---------------|-----------------|-------|
| `downloading` | 0.00 – 0.70     | HuggingFace repo download (skipped on cache hit) |
| `extracting`  | 0.70 – 0.85     | Bundle unpack to local cache (skipped on cache hit) |
| `loading`     | 0.85 – 0.99     | Pipeline construction |
| `ready`       | 1.00 (terminal) | Emitted on success only |

**Flutter** — events from every active `start_model` are multiplexed
through one global `Stream`. Filter by `model_name` to disambiguate
concurrent loads:

```dart
TheStageFlutterSDK.on_progress.listen((event) {
  // event['model_name'] : String  — model handle passed to start_model
  // event['phase']      : String  — 'downloading' | 'extracting' | 'loading' | 'ready'
  // event['progress']   : double  — 0.0 … 1.0, monotonic
});
```

The phase strings, fraction bands and terminal contract are identical
on both surfaces. See [llm.md](./llm.md) for the full event contract.

## Common Workflows

### Speech-to-text, batch

**Flutter:**

```dart
await TheStageFlutterSDK.start_model(
  model_name: 'stt',
  engines_path: 'TheStageAI/thewhisper-large-v3-turbo',
);
final asr = await TheStageFlutterSDK.infer(
  model_name: 'stt',
  input_json: {'audio': pcm_16k_mono, 'language': 'en'},
);
print(asr[0]['transcription']);
```

### Text-to-speech, streaming

The TTS streamer is push-based: the consumer drains audio chunks
concurrently with the producer pushing text, so audio starts playing
the moment the first sentence is synthesized — the typical use case is
piping LLM tokens into TTS as they arrive.

**Flutter:**

```dart
await TheStageFlutterSDK.start_model(
  model_name: 'tts',
  engines_path: 'TheStageAI/neutts-multilingual',
  config: {'voice_id': 'paul', 'language': 'english'},
);

const streamId = 'tts-utterance-1';
final player = TheStageAudioPlayer(sampleRate: 24000)..start();

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

await TheStageFlutterSDK.send(stream_id: streamId, text: 'Hello, world. ');
await TheStageFlutterSDK.send(
  stream_id: streamId,
  text: 'This sentence streams as it synthesizes.',
);
await TheStageFlutterSDK.finish_stream(stream_id: streamId);
await consumer;
```

For an already-known string, call `infer_stream` with the full `text`
and skip `send` / `finish_stream`.

See [voice_agent.md](./voice_agent.md) for the full end-to-end
assistant surface (neural smart-turn end-of-turn detection, barge-in,
sentence-level TTS streaming) and the complete Flutter config-key
reference.

## Audio I/O Contract

All audio crossing the public SDK surface — VAD input, Whisper input,
NeuTTS output — uses **PCM float, mono, samples normalized to
`[-1.0, 1.0]`**. On Kotlin this is `FloatArray`; the Flutter plugin
marshals the same data as `Float32List` (never `Float64List`). Sample
rate depends on the pipeline:

| Pipeline | Direction | Sample rate | Frame / chunking | Notes |
|---|---|---|---|---|
| Silero VAD | input | **16 000 Hz** | exactly **512 samples** per call (32 ms) | Stateful LSTM. Reset state between independent utterances; the model keeps a 64-sample internal carry-over, so you don't overlap chunks yourself. |
| Whisper | input | **16 000 Hz** | any length | Long audio is auto-split into bundle-defined windows (the shipping `thewhisper-large-v3-turbo` bundle uses **10 s** windows). |
| NeuTTS | output | **24 000 Hz** | streamer emits per-sentence chunks (variable length); batch mode emits one buffer of full duration | NeuCodec drives the rate (`hop=320`, `token_rate=50`). |

Practical consequences:

- **The mic stack must run at 16 kHz mono Float for VAD and ASR.**
- **TTS output is always 24 kHz**, even though VAD/ASR are 16 kHz.
  Resample TTS to 16 kHz or drive the player at 24 kHz if you route
  everything through one playback path.

## Initialization

`TheStageAI.registerContext(context)` then
`TheStageAI.initialize(api_token = ...)` (Kotlin), or
`TheStageFlutterSDK.initialize(api_token: ...)` (Flutter), must be
called once before any model is started. The token is validated online
on first use (the device must be reachable then); there is no offline
grace window. A per-process in-memory cache skips re-validation for the
rest of that process, but a fresh app launch re-validates online. See
[licensing.md](./licensing.md) for how devices are identified and
counted on Android (a reinstall may allocate a new `deviceId` unless
Android Auto Backup is enabled; the backend reconciles brief
reinstalls within a reactivation window).

## Model cache & storage

Downloaded models live under the app's private files directory:

| Layer | Contents |
|---|---|
| Download cache (`…/files/Qlip.SDK/hf/<repo_id>/<revision>/sdk-<ver>/<variant>/`) | The fetched `engines.zip` (+ metadata sidecar), keyed per repo + revision + SDK line + device variant |
| Extracted engines (`…/files/Qlip.SDK/engines/<model_type>_sdk-<ver>_<variant>/`) | Unpacked bundle the runtime loads from |

- **To reclaim space, delete the extracted engines dir, not the zip.**
  Re-extraction from the cached zip needs no network; deleting the zip
  forces a full re-download.
- Distinct repos of the same modality (e.g. `whisper-small` vs
  `whisper-large-v3-turbo`) are cached under separate keys and never
  overwrite each other.

## Where things live

- **Prebuilt binaries**: `TheStageCore.aar` + the ONNX Runtime
  AAR at the distribution root.
- **Flutter plugin (Dart)**:
  `plugin/thestage_android_sdk/lib/thestage_android_sdk.dart`
- **Example apps**: `examples/{tts_front_stream, voice_agent,
  voice_agent_custom_nodes, engine_bench}/`
- **One-time setup**: `scripts/setup.sh` (AAR symlinks, QAIRT Genie
  libs, secrets bootstrap — see the top-level `README.md`).

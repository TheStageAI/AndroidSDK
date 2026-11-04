# TheStage Android SDK — Documentation

On-device speech, language, vision and audio inference for
**Android** on Qualcomm Snapdragon. The SDK runs its models on the
Hexagon NPU (language, vision and speech-recognition models on
TheStage's own NPU runtime, the others through the QNN runtime),
falls back to a model's portable **CPU** bundle, where it publishes
one, on a chip it has no NPU bundle for, pulls engines from HuggingFace on first
use, and exposes
a unified `infer` / `infer_stream` API for every pipeline. No server
in the hot path.

This folder is the customer-facing reference for both consumption
surfaces: the native **Kotlin** singleton (`TheStageAI`) and the
**Flutter** plugin (`thestage_android_sdk` → `TheStageFlutterSDK`).

## Table of Contents

- [LLM (Language Model)](./llm.md) — on-device chat (LFM2.5, LFM3,
  Qwen3.5; Qwen3.5-9B on 8 Elite and 8 Elite Gen 5 only) with
  streaming, multi-turn history, MTP and thinking.
- [Whisper ASR](./whisper.md) — speech-to-text with automatic VAD
  chunking and long-audio stitching.
- [VLM (Vision-Language)](./vlm.md) — on-device images + prompt → text
  (LFM2.5-VL, Gemma 4), batch and streaming.
- [NeuTTS](./tts.md) — multilingual neural TTS (9 languages, in a
  nano and a full size) and an English-only nano, with batch +
  push-based streaming.
- [VAD](./vad.md) — Silero VAD: stateful per-chunk speech detection.
- [Streaming](./streaming.md) — TTS / LLM streaming patterns,
  back-pressure, sentence segmentation, Flutter consumers.
- [Voice Agent](./voice_agent.md) — end-to-end voice assistant
  (VAD → STT → LLM → TTS) with neural end-of-turn detection and
  barge-in.
- [Model Management](./model_management.md) — choosing the device,
  availability probing, prefetch, installed models and updates,
  reclaiming space, per-component load/unload, bundled-engine paths,
  and process-memory reporting.
- [AI Packs](./ai_packs.md) — ship models via Google Play AI packs
  (`aipack://` engines source): pack modules, device targeting,
  delivery modes, availability.
- [Speaker Embedding](./speaker_embedding.md) — ReDimNet2 speaker-id:
  enroll + cosine verification, and voice-agent speaker gating.
- [Diarization](./diarization.md) — who spoke when
  (`nemotron-diarization`) and who said what
  (`nemotron-multispeaker`): streaming segments, speaker enrollment,
  and wiring the composite from models you already started.
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

## Supported Devices

Phones with Snapdragon 8 Gen 2 (SM8550), 8 Gen 3 (SM8650), 8 Elite
(SM8750) or 8 Elite Gen 5 (SM8850). A model publishes either one
NPU build per chip or a single NPU build that serves all of them
(the language and vision-language models), and some also publish a
portable CPU build; the SDK downloads the one that fits the phone
(see [Choosing the device](./model_management.md#choosing-the-device)).
The [availability check](./model_management.md#availability) tells
you before a download whether a model has a build for the device.

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
  // `progress` is sent only while downloading; absent elsewhere.
  final p = event['progress'] as num?;
  print('[stt] ${event['phase']}'
      '${p == null ? '' : ' ${(p * 100).toStringAsFixed(0)}%'}');
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

### `model_type`

The examples above pass only `model_name` and `engines_path`, which is
all a published repo needs: the SDK resolves the model type from the
repo id. Pass `model_type` explicitly when loading from a **local
directory** or a repo the SDK does not know, since there is no repo id
to resolve from:

```kotlin
TheStageAI.start_model(
    model_name = "stt",
    engines_path = "/data/local/tmp/my_whisper_bundle",
    model_type = "whisper",
)
```

### `device`

Leave `device` unset: the SDK takes the best bundle the model
publishes for this phone — its NPU bundle where there is one for the
chip, otherwise its portable CPU bundle. Pass `"npu"` or `"cpu"` only
to **require** one; the load then fails, naming the chip and what the
repo publishes, instead of quietly running somewhere else. `"gpu"` is
refused. See
[Model Management → Choosing the device](./model_management.md#choosing-the-device).

## Kotlin ↔ Flutter Quick Reference

The Kotlin singleton (`TheStageAI`) and the Flutter
`TheStageFlutterSDK` mirror each other one-to-one. Dart consumers
always go through the JSON path.

| Operation | Kotlin | Flutter (Dart) |
|---|---|---|
| Initialize | `TheStageAI.registerContext(context)` then `TheStageAI.initialize(api_token = "...")` | `await TheStageFlutterSDK.initialize(api_token: '...')` |
| Start a model | `TheStageAI.start_model(model_name =, engines_path =, device =, config =)` | `await TheStageFlutterSDK.start_model(model_name:, engines_path:, device:, config:)` |
| Stop a model | `TheStageAI.stop_model(model_name = "llm")` | `await TheStageFlutterSDK.stop_model(model_name: 'llm')` |
| Single-shot inference | `TheStageAI.infer(model_name =, input_json =) -> List<Map<String, Any>>` | `await TheStageFlutterSDK.infer(model_name:, input_json:) -> List<Map<String, dynamic>>` |
| Streaming inference | `TheStageAI.infer_stream(model_name =, input_json =) -> Flow<InferenceStreamChunk>` | `TheStageFlutterSDK.infer_stream(model_name:, input_json:, stream_id:?) -> Stream<Map<String, dynamic>>` |
| Push text into a TTS stream | `val s = TheStageAI.open_tts_streamer(model_name = "tts")`; `s.send(text)`; `s.finish()`; collect `s.output` | `await TheStageFlutterSDK.send(stream_id:, text:); await TheStageFlutterSDK.finish_stream(stream_id:)` |
| Cancel a running stream | cancel the collecting coroutine, or `s.cancel()` on a TTS streamer | `await TheStageFlutterSDK.stop_stream(stream_id:)` |
| Push audio into an ASR stream | `TheStageAI.stream_append(model_name =, input_json =)`; `stream_finish(model_name =)` | `await TheStageFlutterSDK.stream_append(model_name:, input_json:)`; `stream_finish(model_name:)` |
| Installed models and updates | `installed_models()`, `available_updates()`, `remove_model(model_type =, repository =)` | same names on `TheStageFlutterSDK` |
| Reclaim space | `TheStageAI.maintain()`; `reset_models()` to clear everything | `await TheStageFlutterSDK.maintain()`; `reset_models()` |
| Load progress | `start_model(on_load_progress = { p: LoadProgress -> … })` | Single global stream `TheStageFlutterSDK.on_progress` (`{model_name, phase}`, plus `progress` while downloading or `status` when parked) |
| Audio buffer type | `FloatArray` | `Float32List` (never `Float64List`) |

## Load Progress

`phase` is the signal to drive your UI from, and it is always
present. `progress` is only sent while a transfer is measurable:

| Phase                      | Progress        | Notes |
|----------------------------|-----------------|-------|
| `downloading`              | 0.00 – 1.00     | HuggingFace repo download (skipped on cache hit) |
| `waiting_for_wifi`         | *absent*        | AI-pack download parked until an unmetered network. The user can act: prompt them to join Wi-Fi |
| `waiting_for_confirmation` | *absent*        | AI-pack download needs the user's OK for metered data. Show Play's confirmation dialog |
| `extracting`               | *absent*        | Bundle unpack to local cache (skipped on cache hit) |
| `loading`                  | *absent*        | Pipeline construction, including first-run NPU context compile |
| `ready`                    | 1.00 (terminal) | Emitted on success only |

Unpacking and NPU compilation report nothing
intermediate, so those phases send no `progress` rather than a
number that would sit frozen. Bind a determinate bar when
`progress` is present and an indeterminate one when it is absent —
in Flutter, `LinearProgressIndicator(value:)` takes `null` for
exactly this.

**Flutter** — events from every active `start_model` are multiplexed
through one global `Stream`. Filter by `model_name` to disambiguate
concurrent loads:

```dart
TheStageFlutterSDK.on_progress.listen((event) {
  // event['model_name'] : String  — model handle passed to start_model
  // event['phase']      : String  — always present; see the table above
  // event['progress']   : double? — 0.0 … 1.0 while downloading;
  //                                 ABSENT on the other phases
  // event['status']     : String? — 'waiting_for_wifi' |
  //                                 'waiting_for_confirmation'
  // event['downloaded_bytes'] : int?  — during 'downloading' only
  // event['total_bytes']      : int?  — during 'downloading' only

  final phase = event['phase'] as String?;
  final p = (event['progress'] as num?)?.toDouble();
  // `p == null` is the cue for an indeterminate indicator, not a
  // reason to reset the bar to zero.
});
```

### Byte counters

`progress` alone cannot say whether 40% means 40 MB or 4 GB. During
the `downloading` phase the event also carries `downloaded_bytes` and
`total_bytes`, so an app can show "120 MB of 300 MB" or warn before a
large download on a metered connection.

Both keys are **absent** — not null, not zero — when the server
declared no `Content-Length`, so check for presence rather than
trusting a value:

```dart
final total = event['total_bytes'] as int?;
if (total != null) {
  final done = event['downloaded_bytes'] as int;
  label = '${done >> 20} MB of ${total >> 20} MB';
}
```

In Kotlin the same values are `LoadProgress.downloaded_bytes` and
`LoadProgress.total_bytes`, both `Long?`.

The phase strings and the terminal contract are identical on both
surfaces, and on both a fraction is present only while downloading. See
[Model Management](./model_management.md) for loading, prefetch and
the installed-model lifecycle.

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
final player = TSAudioPlayer(sampleRate: 24000)..start();

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
counted on Android (the `deviceId` is derived from `ANDROID_ID`, so
it survives reinstall and "clear data" and resets only on factory
reset).

## Model cache & storage

Downloaded models live in the app's private files directory, out of
reach of other apps and of the user's media:

| Layer | Contents |
|---|---|
| Download cache | The fetched archive, keyed per repo + pinned commit |
| Extracted engines | Unpacked bundle the runtime loads from, keyed per repo + pinned commit + variant |

A local bundle and a Play AI pack are staged per model type and
variant instead: neither has a repo commit to key on.

- **Every repo has its own slot.** Repos that share a model type — all
  the text LLMs are `the-stage-llm` — are installed side by side, so
  switching between them loads from disk after the first download.
- **Nothing is keyed on the SDK version**, so upgrading the SDK
  re-downloads nothing while the pins stay where they are.
- **A load never replaces what is installed.** When this build pins a
  newer commit, `available_updates()` reports it and the installed
  bundle keeps serving until the app takes the update; the replaced
  revision is then reclaimed. See
  [Model Management → Installed models and updates](./model_management.md#installed-models-and-updates).
- **Reclaim space through the SDK**, not by deleting directories:
  `remove_model` for one model, `maintain()` for whatever nothing
  claims, `reset_models()` to start over.

## Upgrading from 1.0.x

- Kotlin `LoadProgress.fraction` is `Double?`: it carries transfer
  progress (0..1) only while `downloading` and `1.0` on `ready`, and
  is `null` in every other phase. Drive the UI from `phase`.
- Dart `start_model` `device` defaults to `''`, the best available
  bundle for the phone (it was `'gpu'`). `'gpu'` is refused; `'npu'`
  and `'cpu'` are constraints that fail when the model publishes no
  such bundle.
- A load never replaces an installed bundle. Take updates with
  `available_updates()` and `prefetch_model(replace_existing: true)`.
- Models are cached per repo and pinned commit. Copies cached by 1.0.x
  are not reused: each model downloads once more on its first load
  after the upgrade. `reset_models()`, which clears every staged
  model, also reclaims the old copies.
- The `deviceId` changes once: an install upgrading from 1.0.x
  registers as a new device, then keeps the new id across reinstalls
  (see [licensing.md](./licensing.md)).
- Dart `TTSController.downloadProgress` is `double?` (null outside
  `downloading`). Its `modelType` defaults to `'neutts'` (was
  `'neutts-multilingual'`) and its `revision` to `''`, the pinned
  commit (was `'develop'`).
- Voice agent: every `*_device` field of `TheStageAgentConfig` (and
  the matching Flutter config keys) defaults to `""`, the best
  available bundle for each component (they were `"npu"` / `"cpu"`).
  A 1.0.x agent config that forces device `"npu"` fails for
  components that publish only a CPU bundle, such as VAD — drop those
  overrides.
- Voice agent `set_voice` reports failures: Kotlin throws, and the
  Flutter call completes with an error, for an unknown voice id or a
  `voice_dir` without `voice.json`. The current voice stays.
- The Dart names `TheStageVoiceAgentFlutter`, `TheStageAgentNode`,
  `TheStageAgentState`, `TheStageAudioPlayer` and camelCase members
  such as `llmDeltas` or `setVoice` still compile as deprecated
  aliases of `TSVoiceAgent`, `TSAgentNode`, `TSAgentState`,
  `TSAudioPlayer` and the snake_case names in
  [voice_agent.md](./voice_agent.md).
- Voice-agent config: the Flutter keys `turn_detection_mode` and
  `allow_interruptions: false` are still read, as `turn_end_mode` and
  `interrupt_mode: 'none'`. In Kotlin, `turn_detection_mode`,
  `interrupt_trigger` and `allow_interruptions` are read-only
  properties derived from `turn_end_mode` and `interrupt_mode`.
- A voice agent on the on-device LLM gets the built-in `voice` tool
  preset (weather, time, search, Wikipedia, calculator, phone
  actions) and `DefaultTools.voice_system_prompt` when the config
  sets neither. Set `llm_tools: 'none'` for replies without tools; the
  new `tool_calling` state needs a case in an exhaustive switch over
  `TSAgentState` (see [voice_agent.md](./voice_agent.md#tools)).

## Where things live

- **Prebuilt binaries**: `TheStageCore.aar` + the ONNX Runtime
  AAR at the distribution root.
- **Flutter plugin (Dart)**:
  `plugin/thestage_android_sdk/lib/thestage_android_sdk.dart`
- **Example apps**: `examples/{engine_bench, tutor_small_llms,
  tutor_tts, voice_agent, voice_agent_custom_nodes}/`
- **One-time setup**: `scripts/setup.sh` (AAR symlinks, QAIRT Genie
  libs, secrets bootstrap — see the top-level `README.md`).

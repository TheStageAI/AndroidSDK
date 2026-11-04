# TheStage Android SDK

On-device speech, language, vision and audio inference for **Android**
on Qualcomm Snapdragon. The SDK runs compiled engines on the Hexagon
NPU (TheStage's own NPU runtime for the language, vision and
speech-recognition models; the QNN runtime for the others), uses a
model's portable **CPU** build where it publishes one and the phone's
chip has no NPU build, downloads engines from HuggingFace on first
use, and exposes a unified
`infer` / `infer_stream` API for every pipeline. No server in the hot
path.

| | |
|---|---|
| **Version** | **`1.1.0`** — pin this tag (`ref: v1.1.0`); do not float |
| **Platform** | Android, `minSdk 28`, `compileSdk 35`, **arm64-v8a** only |
| **Backend** | Hexagon NPU (TheStage NPU runtime and QNN / HTP); a portable CPU build where a model publishes one |
| **Token** | one online check per process (cached in-memory); a fresh launch re-validates online |

## Table of contents

- [What's in this repo](#whats-in-this-repo)
- [Capabilities & model fleet](#capabilities--model-fleet)
- [Quick start — the Flutter examples](#quick-start--the-flutter-examples)
- [Prerequisites](#prerequisites)
- [Use the SDK in your own app](#use-the-sdk-in-your-own-app)
- [Mental model](#mental-model)
- [Contracts](#contracts)
- [Upgrading from 1.0.x](#upgrading-from-10x)
- [Documentation map](#documentation-map)
- [Troubleshooting](#troubleshooting)
- [Secrets](#secrets) · [License](#license)

## What's in this repo

- `RELEASE.md` — what's new, the AAR checksums and the model commits
  this version pins.
- `TheStageCore.aar` — pre-built SDK binary (inference engine, license
  gate, ONNX Runtime / QNN / Genie runtimes). Opaque; you link it, you
  don't build it.
- `onnxruntime-android.aar` — the QNN-enabled ONNX Runtime AAR the core
  links against. Supplied by the app at runtime.
- `plugin/thestage_android_sdk/` — Flutter plugin over platform
  channels. Your app module supplies the AARs (see
  [Flutter](#flutter)).
- `examples/tutor_tts/` — mixed-language streaming TTS: a language tutor
  that switches language per span (Flutter). **Start here.**
- `examples/voice_agent/` — full voice-assistant loop, mic → VAD → STT
  → LLM → streaming TTS (Flutter).
- `examples/voice_agent_custom_nodes/` — the voice agent plus custom
  graph nodes + ephemeral VLM captions + screen recording (Flutter).
- `examples/tutor_small_llms/` — a small LLM turns a receipt, a chat or
  an SMS into structured data (Flutter).
- `examples/engine_bench/` — on-device LLM / TTS / ASR / VLM benchmark
  with JSON export (Flutter).
- `docs/` — per-pipeline reference guides.
- `scripts/setup.sh` — one-time host setup (AAR symlinks + secrets
  bootstrap for the Flutter examples).
- `VERSION` — the SDK line this checkout ships (`1.1.0`).

---

## Capabilities & model fleet

Everything below is the **`1.1.0`** fleet. Pass the HF id as
`engines_path`; the SDK downloads and caches it on first start and
resolves the `model_type` from the repo id, so you pass `model_type`
only for a local bundle. `model_name` is your own handle for the
loaded model.

| Task | HF engines | `model_type` | Notes |
| --- | --- | --- | --- |
| Chat LLM | `TheStageAI/LFM2.5-230M` · `LFM2.5-350M` · `LFM2.5-1.2B` · `LFM3-1.7B` · `Qwen3.5-0.8B` · `Qwen3.5-2B` · `Qwen3.5-4B` · `Qwen3.5-9B` | `the-stage-llm` | on-device chat; MTP / thinking per model; Qwen3.5-9B on 8 Elite and 8 Elite Gen 5 only, see [llm.md](./docs/llm.md) |
| VLM | `TheStageAI/LFM2.5-VL-450M` · `LFM2.5-VL-1.6B` · `gemma-4-E2B-it` | `lfm2-vl` · `gemma4-vl` | images + prompt → text, see [vlm.md](./docs/vlm.md) |
| ASR | `TheStageAI/thewhisper-large-v3-turbo` | `whisper` | any length; SDK windows long audio |
| TTS | `TheStageAI/neutts-nano-multilingual` · `neutts-multilingual` · `neutts` | `neutts` | 9 languages (`neutts` is English-only), see [tts.md](./docs/tts.md) |
| VAD | `TheStageAI/silero-vad` | `silero-vad` | 512-sample chunks @ 16 kHz |
| Turn detect | `TheStageAI/smart-turn-v3` | `smart-turn` | DNN end-of-turn; used by the voice agent |
| Speaker ID | `TheStageAI/redimnet2` | `speaker-id` | 192-d embedding, 2 s window |
| Diarization | `TheStageAI/Nemotron-3-Diarization` | `nemotron-diarization` | who spoke when; streaming segments, see [diarization.md](./docs/diarization.md) |
| Full agent | compose the above | — | see [voice_agent.md](./docs/voice_agent.md) |

Omit `revision` in normal apps — the SDK resolves each repo to the
commit this SDK version pins (see [Revisions](#revisions)).
Model cards (contracts + acknowledgments):
[huggingface.co/TheStageAI](https://huggingface.co/TheStageAI).

---

## Quick start — the Flutter examples

```bash
# 1. One-time host setup: symlink the AARs into the plugin and
#    bootstrap each example's secrets.json. Idempotent.
./scripts/setup.sh

# 2. Put your TheStage API token (TS_API_TOKEN) into the
#    secrets.json that setup.sh created.
$EDITOR examples/tutor_tts/secrets.json

# 3. Build & run on a connected Snapdragon device.
cd examples/tutor_tts
flutter pub get
flutter run --release \
    --dart-define-from-file=secrets.json \
    -d <YOUR_DEVICE_ID>
```

In the app, tap **Load model** (the first load downloads
`neutts-nano-multilingual`), pick a phrase, then **Play**.
`flutter devices` lists attached devices. The other examples follow
the same recipe (`examples/voice_agent` runs its LLM on-device by
default; `OPENAI_API_KEY` in its `secrets.json` is needed only for the
remote LLM provider). See each example's `README.md` for app-specific notes.

---

## Prerequisites

| Requirement | Minimum | Notes |
|-------------|---------|-------|
| Android device | Android 9 (API 28) | physical Qualcomm Snapdragon, arm64-v8a |
| Android SDK (compile) | API 35 | |
| Flutter (only for the Flutter examples) | 3.38 | with Dart 3.10.7+ (the voice-agent examples need it; the plugin alone needs Dart 3.5) |
| JDK | 17 | |
| Qualcomm QNN runtime | 2.51.0 | `com.qualcomm.qti:qnn-runtime:2.51.0` from Qualcomm's Maven repo; your app module declares it, Flutter or native (see below) |
| Qualcomm QAIRT SDK (optional) | 2.51.0 | only for the optional libs in [QAIRT runtime libs](#qualcomm-qairt-runtime-libs-genie-backend); must be 2.51.0 |

The NPU backend requires one of the supported Snapdragon chips (8 Gen 2,
8 Gen 3, 8 Elite, 8 Elite Gen 5). On other hardware only the models
that publish a portable CPU build load; the others fail with an error
naming the chip and what the model publishes. You'll need a TheStage API token
from [app.thestage.ai](https://app.thestage.ai) — it's validated online
once per process (cached in-memory); a fresh launch re-validates online.

---

## Use the SDK in your own app

### Flutter

Add the plugin as a `git:` dependency in your app's `pubspec.yaml`,
pinned to the tag:

```yaml
dependencies:
  thestage_android_sdk:
    git:
      url: https://github.com/TheStageAI/AndroidSDK.git
      path: plugin/thestage_android_sdk
      ref: v1.1.0
```

The plugin declares the prebuilt AARs `compileOnly`, so your **app
module** must supply them at runtime. Copy `TheStageCore.aar` and the
ONNX Runtime AAR into your app's `libs/` and wire them up as in the
"Native Kotlin / Gradle" section below, then:

```dart
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

await TheStageFlutterSDK.initialize(api_token: 'th_…');

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

The fastest way to see a real app is to copy one of the `examples/`
apps.

### Native Kotlin / Gradle

You can consume the AARs directly from a Kotlin/Android app, no Flutter
involved. Copy the two prebuilt AARs into your app module's `libs/`.

The Qualcomm QNN runtime (the signed per-SoC HTP skel libraries the NPU
backend needs) is published on Qualcomm's public Maven repository — no
login required. Declare that repository in your **`settings.gradle.kts`**
alongside the usual ones:

```kotlin
// settings.gradle.kts
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        // Qualcomm QNN / QAIRT runtime artifacts (public, no auth).
        maven { url = uri("https://qpm-download.qualcomm.com/maven/release") }
    }
}
```

Then in your app module's `build.gradle.kts`:

```kotlin
dependencies {
    // The precompiled TheStage core (opaque engine/license/runtime)
    // and the QNN-enabled ONNX Runtime AAR.
    implementation(files("libs/TheStageCore.aar"))
    implementation(files("libs/onnxruntime-android.aar"))

    // Qualcomm QNN runtime — 19 libs: libQnnHtp / HtpPrepare / System /
    // Gpu / Dsp plus the per-SoC HTP skel + stub libraries
    // (V68, V69, V73, V75, V79, V81, and Dsp V66). Resolved from the
    // Qualcomm Maven repo declared above.
    implementation("com.qualcomm.qti:qnn-runtime:2.51.0")

    // Transitive deps of the core (not pulled via files(...)).
    implementation("com.google.code.gson:gson:2.11.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation(
        "org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0"
    )
}
```

> **No currently published model needs more than the `qnn-runtime`
> Maven artifact.** The extra QAIRT libs are only for a bundle that
> wants the `GenAiTransformer` Genie backend — see
> **[Qualcomm QAIRT runtime libs](#qualcomm-qairt-runtime-libs-genie-backend)**
> below.

Because both `TheStageCore.aar` and `onnxruntime-android.aar` bundle
native `.so` libraries, add a `packaging` block to your app module so
the merge picks one copy of each duplicate, and restrict the ABI to
`arm64-v8a`:

```kotlin
android {
    defaultConfig {
        minSdk = 28
        ndk { abiFilters += "arm64-v8a" }
    }
    packaging {
        jniLibs.pickFirsts.add("lib/arm64-v8a/libonnxruntime.so")
        jniLibs.pickFirsts.add("lib/arm64-v8a/libonnxruntime4j_jni.so")
        jniLibs.pickFirsts.add("lib/arm64-v8a/libc++_shared.so")
    }
}
```

QNN's FastRPC skel libraries load from an APK only when they are
extracted at install time, so set `android:extractNativeLibs="true"`
on your `<application>` (or `useLegacyPackaging = true` in the
`jniLibs` packaging block). Then drive the singleton from Kotlin —
register the app `Context` once, then initialize with your token:

```kotlin
// Once, at app start (e.g. Application.onCreate).
TheStageAI.registerContext(context)

// Suspend — validates the token online (once per process).
TheStageAI.initialize(api_token = "th_…")

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
```

`registerContext` is native-only (the Flutter plugin registers the
`Context` for you). `initialize`, `start_model`, `infer` and
`infer_stream` are `suspend` functions — call them from a coroutine.

### Qualcomm QAIRT runtime libs (Genie backend)

**You probably do not need this.** Every model this SDK currently
publishes runs with only the `com.qualcomm.qti:qnn-runtime` Maven
artifact, which resolves with no account and no manual steps —
including the Genie-backed ones. Genie requests the `QnnHtp` backend,
and `QnnHtp` comes from Maven.

Most of the libs below belong to a different Genie backend
(`GenAiTransformer`) that no currently published bundle asks for. The
exception is `libQnnHtpNetRunExtensions.so`: the NeuTTS bundles use it
to apply their HTP performance settings. Without it NeuTTS still runs,
at the default HTP settings. Set `QAIRT` to get it, if you are running
a bundle that needs the other libs, or if a Genie pipeline fails with
the `dlopen` error at the bottom of this section.

If you do need them, they are not on Maven and this SDK does **not**
redistribute them, because they are Qualcomm's to license. You copy
them from your own QAIRT install.

#### 1. Get the QAIRT SDK (version 2.51.0)

Download **Qualcomm AI Runtime SDK** (QAIRT — the Qualcomm AI Engine
Direct / QNN runtime), version `2.51.0`, via **Qualcomm Package
Manager**: [qpm.qualcomm.com](https://qpm.qualcomm.com/). A free
Qualcomm account is required; search for "Qualcomm AI Runtime SDK".

Install it and note the versioned directory, e.g.
`~/Qualcomm/AIStack/QAIRT/2.51.0.260929`. The libs live under
`<install>/lib/aarch64-android/`.

**2.51.0 specifically.** `TheStageCore.aar` ships its own Genie build
compiled against QAIRT 2.51.0, so backend libs from another QAIRT are
an ABI mismatch. You do **not** need stock `libGenie.so`.

> This pin is about the **libs you install** — not about model
> bundles. The bundles this SDK downloads are compiled with an older
> QAIRT and load correctly on 2.51: an older context binary is
> forward-compatible, and only a *newer* one is rejected (with
> `Could not create context from binary … err 5000`). You never have
> to match your QAIRT install to the bundles.

#### 2. Copy the libs in

```bash
QAIRT=~/Qualcomm/AIStack/QAIRT/2.51.0.260929 ./scripts/setup.sh
```

That copies them into the plugin's `jniLibs/arm64-v8a/`, from where
AGP merges them into every app you build. (To do it by hand instead,
copy them into your own app's `src/main/jniLibs/arm64-v8a/`.)

| Library | Role | In 2.51 |
|---|---|---|
| `libQnnGenAiTransformer.so` | GenAI transformer backend | yes |
| `libQnnGenAiTransformerModel.so` | GenAI transformer model backend | yes |
| `libQnnCpu.so` | QNN CPU fallback backend | yes |
| `libQnnHtpNetRunExtensions.so` | HTP performance settings (NeuTTS) | yes |
| `libQnnGenAiTransformerCpuOpPkg.so` | GenAI transformer CPU op package | **no — dropped by Qualcomm; skipped automatically** |

`setup.sh` treats the first four as required and the last as
optional, so a 2.51 install is not reported as broken. On older QAIRT
installs that still ship it, it is copied too.

#### 3. Check it worked

```bash
ls plugin/thestage_android_sdk/android/src/main/jniLibs/arm64-v8a/
# libQnnCpu.so  libQnnGenAiTransformer.so  libQnnGenAiTransformerModel.so
# libQnnHtpNetRunExtensions.so
```

If a Genie pipeline is still missing them at runtime it fails on first
use with:

```
dlopen failed: library "libQnnGenAiTransformer.so" not found
```

The Snapdragon-only QNN NPU backend (`qnn-runtime` Maven artifact
above) is what everything else uses; only the Genie pipelines need
this extra QAIRT copy step.

---

## Mental model

### Lifecycle

1. **`initialize(api_token:)`** — online token check + device seat
   registration. Fails offline / on network errors. Once per process
   when reachable; after success, **inference is on-device** for that
   process. (Native: call `registerContext(context)` first.)
2. **Load** — `start_model(model_name:, engines_path:)`. The first
   load downloads the commit this SDK pins into the app's internal
   files dir (not on external storage, excluded from user-visible
   media); later loads read it from disk, with no network. Leave
   `device` unset for the best build for the phone — see
   [Choosing the device](./docs/model_management.md#choosing-the-device).
3. **Infer** — batch `infer` or streaming `infer_stream`; push text
   into TTS with `send` → `finish_stream` (Flutter) or
   `open_tts_streamer` (Kotlin).
4. **Stop** — `stop_model(model_name:)` to free the engine's memory.

### Revisions

Omit `revision` in normal apps. Each SDK release pins every model it
supports to an exact HF commit, so the bytes a release downloads never
change under it; a blank `revision` resolves that pin. Passing a
revision overrides the pin.

A load never replaces an installed model, even when a newer release
pins a newer commit: `available_updates()` reports it and your app
takes it when it chooses. See
[Installed models and updates](./docs/model_management.md#installed-models-and-updates).

### Init & seats (product)

- A seat is `(api_token, deviceId)` — see [licensing.md](./docs/licensing.md).
- The `deviceId` is derived from Android's `ANDROID_ID`, scoped per
  app: it survives reinstall and "clear data" and resets only on a
  factory reset. The SDK owns it; do not build your own device
  registry.
- Pricing / plans: [app.thestage.ai](https://app.thestage.ai).

---

## Contracts

### Audio I/O

All public audio is **PCM mono**, samples in **`[-1.0, 1.0]`**.

| Pipeline | Direction | Rate | Framing |
| --- | --- | --- | --- |
| `vad` (Silero) | in | **16 kHz** | exactly **512** samples / call (stateful) |
| `stt` (Whisper) | in | **16 kHz** | any length; SDK windows long audio |
| `tts` (NeuTTS) | out | **24 kHz** | streamer = chunks; batch = one buffer |
| `speaker-id` | in | **16 kHz** | **2.0 s** window (pad / trim) |

The agent mic path is 16 kHz; TTS playback is 24 kHz — resample at the
edge if you mix them. Flutter passes audio as **`Float32List`** (never
`Float64List`).

### Load progress

Subscribe to `TheStageFlutterSDK.on_progress` (Flutter). `phase` is
always present; `progress` (0…1) is sent only while downloading:

| Phase | `progress` | Notes |
| --- | --- | --- |
| `downloading` | 0.00 – 1.00 | HF fetch (skipped on cache hit) |
| `waiting_for_wifi` / `waiting_for_confirmation` | absent | an AI-pack download parked by Play |
| `extracting` | absent | unpack (skipped on cache hit) |
| `loading` | absent | pipeline construction |
| `ready` | 1.00 | success only |

Bind a determinate bar while `progress` is present and an
indeterminate one otherwise. See
[Load Progress](./docs/README.md#load-progress) for the full contract.

During `downloading` the event also carries `downloaded_bytes` and
`total_bytes`, so you can show "120 MB of 300 MB" rather than a bare
percentage. Both keys are **absent** when the server declared no
`Content-Length` — check for presence rather than trusting a value.

### Flutter ↔ native parity

| Operation | Native (Kotlin) | Flutter (Dart) |
| --- | --- | --- |
| Register context | `TheStageAI.registerContext(ctx)` | (automatic) |
| Initialize | `TheStageAI.initialize(api_token = …)` | `TheStageFlutterSDK.initialize(api_token: …)` |
| Start | `TheStageAI.start_model(...)` | `start_model(...)` |
| Stop | `TheStageAI.stop_model(model_name = …)` | `stop_model(model_name: …)` |
| Batch | `TheStageAI.infer(model_name, input_json)` | `infer(...)` |
| Stream | `TheStageAI.infer_stream(...)` → `Flow<InferenceStreamChunk>` | `infer_stream(...)` → `Stream` |
| TTS push | `TheStageAI.open_tts_streamer(model_name = …)` → `send` / `finish` / `cancel`, audio on `output` | `send` / `finish_stream` / `stop_stream` |
| Progress | `start_model(on_load_progress = { p: LoadProgress -> … })` | global `on_progress` |
| Installed / updates | `installed_models()` / `available_updates()` | same |
| Free space | `remove_model(...)` / `maintain()` / `reset_models()` | same |

Both surfaces use the same `model_name` strings and the same
`input_json` shape; the Flutter path is JSON-only.

---

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
  (see [licensing.md](./docs/licensing.md)).
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
  [voice_agent.md](./docs/voice_agent.md).
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
  `TSAgentState` (see [voice_agent.md](./docs/voice_agent.md#tools)).

---

## Documentation map

| Doc | Open when you need… |
| --- | --- |
| [llm.md](./docs/llm.md) | Chat, streaming tokens, multi-turn, MTP, thinking |
| [whisper.md](./docs/whisper.md) | ASR, VAD chunking, languages |
| [vlm.md](./docs/vlm.md) | On-device image + prompt → text |
| [tts.md](./docs/tts.md) | NeuTTS voices + streaming (multilingual and English nano) |
| [vad.md](./docs/vad.md) | Silero chunk contract |
| [streaming.md](./docs/streaming.md) | Back-pressure, sentence segmentation |
| [voice_agent.md](./docs/voice_agent.md) | Full loop, barge-in, smart-turn knobs |
| [speaker_embedding.md](./docs/speaker_embedding.md) | Enroll / verify |
| [diarization.md](./docs/diarization.md) | Who spoke when, who said what |
| [model_management.md](./docs/model_management.md) | Choosing the device, availability, updates, freeing space, offloading |
| [ai_packs.md](./docs/ai_packs.md) | Ship models via Google Play AI packs |
| [licensing.md](./docs/licensing.md) | Token, seats, offline rules |
| [logging.md](./docs/logging.md) | Support breadcrumbs |
| [product_terms.md](./docs/product_terms.md) | Commercial / legal pointer |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `Token validation failed` at first start | Missing / bad token, or offline on first run | Pass a valid token; be online for the one-time check |
| `dlopen failed: … libQnnGenAiTransformer.so not found` | A bundle that wants the `GenAiTransformer` Genie backend, without the QAIRT libs | Copy the QAIRT 2.51 libs — see [QAIRT runtime libs](#qualcomm-qairt-runtime-libs-genie-backend). No currently published model needs them |
| An error-level log line containing `does not support usesCrossAttention` on a VLM call | Benign. Logged by the bundled runtime; generation is unaffected | Ignore it |
| `Could not create context from binary … err 5000` | A bundle compiled with a newer QAIRT than the SDK's runtime | Update the SDK; side-loaded bundles must be compiled with QAIRT ≤ 2.51 |
| FastRPC / NPU skel won't load in a native app | `.so` compressed in the APK | Set `android:extractNativeLibs="true"` |
| Duplicate `.so` at merge | ORT + core ship the same lib | Add the `jniLibs.pickFirsts` block above |
| First infer very slow | HF download | Wait for `ready`; later runs use the cache |
| Load fails naming the chip and what the repo publishes | `device` asks for a build the model does not publish for this phone | Leave `device` unset for the best available build |
| Phone runs low on storage | Models stay in app storage until removed | `remove_model` for one model, `maintain()` for what nothing uses |
| Flutter audio glitches / NaNs | `Float64List` or wrong rate | Use `Float32List`; match the audio table above |
| Flutter git dependency won't resolve | Floating ref | Pin `ref: v1.1.0` |

---

## Secrets

The Flutter example apps read tokens at build time via
`String.fromEnvironment(...)` and `--dart-define-from-file=secrets.json`.
Each ships a `secrets.example.json` template — copy it to `secrets.json`
and fill in your keys. `secrets.json` is covered by `.gitignore`; real
keys never belong in source.

## License

See [LICENSE](LICENSE).

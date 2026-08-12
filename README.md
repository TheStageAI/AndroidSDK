# TheStage Android SDK

On-device speech, language and audio inference for **Android** on
Qualcomm Snapdragon. The SDK runs compiled engines on the Hexagon NPU
(HTP, via the QNN runtime) with automatic **GPU / CPU fallback**,
downloads engines from HuggingFace on first use, and exposes a unified
`infer` / `infer_stream` API for every pipeline. No server in the hot
path.

| | |
|---|---|
| **Version** | **`1.0.0`** — pin this tag (`ref: v1.0.0`); do not float |
| **Platform** | Android, `minSdk 28`, `compileSdk 35`, **arm64-v8a** only |
| **Backend** | Hexagon NPU (QNN / HTP) with automatic GPU / CPU fallback |
| **Token** | one online check per process (cached in-memory); a fresh launch re-validates online |

## Table of contents

- [What's in this repo](#whats-in-this-repo)
- [Capabilities & model fleet](#capabilities--model-fleet)
- [Quick start — the Flutter examples](#quick-start--the-flutter-examples)
- [Prerequisites](#prerequisites)
- [Use the SDK in your own app](#use-the-sdk-in-your-own-app)
- [Mental model](#mental-model)
- [Contracts](#contracts)
- [Documentation map](#documentation-map)
- [Troubleshooting](#troubleshooting)
- [Secrets](#secrets) · [License](#license)

## What's in this repo

- `TheStageCore.aar` — pre-built SDK binary (inference engine, license
  gate, ONNX Runtime / QNN / Genie runtimes). Opaque; you link it, you
  don't build it.
- `onnxruntime-android.aar` — the QNN-enabled ONNX Runtime AAR the core
  links against. Supplied by the app at runtime.
- `plugin/thestage_android_sdk/` — Flutter plugin over platform
  channels. Bundles the native SDK; nothing to build.
- `examples/tts_front_stream/` — streaming neural TTS demo (Flutter).
  **Start here.**
- `examples/voice_agent/` — full voice-assistant loop, mic → VAD → STT
  → LLM → streaming TTS (Flutter).
- `examples/voice_agent_custom_nodes/` — the voice agent plus custom
  graph nodes + ephemeral VLM captions + screen recording (Flutter).
- `examples/engine_bench/` — on-device TTS / ASR / VLM benchmark with
  JSON export (Flutter).
- `docs/` — per-pipeline reference guides.
- `scripts/setup.sh` — one-time host setup (AAR symlinks + secrets
  bootstrap for the Flutter examples).
- `VERSION` — the SDK line this checkout ships (`1.0.0`).

---

## Capabilities & model fleet

Everything below is the **`1.0.0`** fleet. Pass the HF id as
`engines_path`; the SDK downloads and caches it on first start.

| Task | HF engines | `model_name` | Notes |
| --- | --- | --- | --- |
| Chat LLM **(coming soon)** | `TheStageAI/Qwen3-0.6B` · `LFM2.5-230M` | `llm` | on-device chat LLM |
| ASR | `TheStageAI/thewhisper-large-v3-turbo` | `stt` | any length; SDK windows long audio |
| TTS | `TheStageAI/neutts-multilingual` | `tts` | multilingual phonemizes internally |
| VAD | `TheStageAI/silero-vad` | `vad` | 512-sample chunks @ 16 kHz |
| Turn detect | `TheStageAI/smart-turn-v3` | via voice agent | DNN end-of-turn |
| Speaker ID | `TheStageAI/redimnet2` | `speaker-id` | 192-d embedding, 2 s window |
| Full agent | compose the above | — | see [voice_agent.md](./docs/voice_agent.md) |

Omit `revision` in normal apps — the SDK resolves each repo's default
branch (`android` / `main` / `develop`) via an internal map (see
[Revisions](#revisions)).
Model cards (contracts + acknowledgments):
[huggingface.co/TheStageAI](https://huggingface.co/TheStageAI).

---

## Quick start — the Flutter examples

```bash
# 1. One-time host setup: symlink the AARs into the plugin and
#    bootstrap each example's secrets.json. Idempotent.
./scripts/setup.sh

# 2. Drop your API keys into the example you want to run.
cp examples/tts_front_stream/secrets.example.json \
   examples/tts_front_stream/secrets.json
$EDITOR examples/tts_front_stream/secrets.json

# 3. Build & run on a connected Snapdragon device.
cd examples/tts_front_stream
flutter pub get
flutter run --release \
    --dart-define-from-file=secrets.json \
    -d <YOUR_DEVICE_ID>
```

`flutter devices` lists attached devices. `examples/voice_agent`
follows the same recipe (it additionally needs `OPENAI_API_KEY` in its
`secrets.json`). See each example's `README.md` for app-specific notes.

---

## Prerequisites

| Requirement | Minimum | Notes |
|-------------|---------|-------|
| Android device | Android 9 (API 28) | physical Qualcomm Snapdragon, arm64-v8a |
| Android SDK (compile) | API 35 | |
| Flutter (only for the Flutter examples) | 3.24 | with a matching Dart 3.5+ |
| JDK | 17 | |

The NPU backend requires a Snapdragon SoC with a Hexagon DSP; on other
hardware the SDK falls back to GPU/CPU. You'll need a TheStage API token
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
      ref: v1.0.0
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
    implementation("com.qualcomm.qti:qnn-runtime:2.42.0")

    // Transitive deps of the core (not pulled via files(...)).
    implementation("com.google.code.gson:gson:2.11.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation(
        "org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0"
    )
}
```

> **The `qnn-runtime` Maven artifact does NOT contain the Genie
> backend libraries.** If you use any Genie/Stagenie-backed pipeline
> (the on-device LLM and NeuTTS Genie paths), you must additionally copy
> five QAIRT runtime libs from a Qualcomm QAIRT SDK install — see
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

The Genie/Stagenie backend that drives the on-device LLM and the NeuTTS
Genie path depends on four native libraries that are **not** in the
`com.qualcomm.qti:qnn-runtime` Maven artifact and that this SDK does
**not** redistribute:

| Library | Role |
|---|---|
| `libQnnGenAiTransformer.so` | GenAI transformer backend |
| `libQnnGenAiTransformerCpuOpPkg.so` | GenAI transformer CPU op package |
| `libQnnGenAiTransformerModel.so` | GenAI transformer model backend |
| `libQnnCpu.so` | QNN CPU fallback backend |

The Genie generation runtime itself is **not** in this list — it ships
as `libStagenie.so` inside `TheStageCore.aar` (a patched Genie build).
You do not need stock `libGenie.so` from QAIRT.

You must obtain these from a **Qualcomm QAIRT SDK 2.42** install
(e.g. `~/Qualcomm/AIStack/QAIRT/2.42.0.251225`, under
`lib/aarch64-android/`) and copy them into your app's — or the
plugin's — `jniLibs/arm64-v8a/`. The bundled `scripts/setup.sh` does
this for you when the `QAIRT` env var points at your install:

```bash
QAIRT=~/Qualcomm/AIStack/QAIRT/2.42.0.251225 ./scripts/setup.sh
```

**Getting the QAIRT SDK:** download the **Qualcomm AI Runtime SDK**
(QAIRT — the Qualcomm AI Engine Direct / QNN runtime), version
`2.42.0`, from Qualcomm's developer site via **Qualcomm Package
Manager** ([qpm.qualcomm.com](https://qpm.qualcomm.com/) — a free
Qualcomm account is required; search for "Qualcomm AI Runtime SDK").
Install it, then set `QAIRT` to the versioned install directory
(e.g. `~/Qualcomm/AIStack/QAIRT/2.42.0.251225`) and re-run
`setup.sh`; the libs it copies live under
`$QAIRT/lib/aarch64-android/`.

**Version 2.42.0 is required** — the shipped `libStagenie.so` inside
`TheStageCore.aar` is built against QAIRT 2.42.0 and is coupled to
that runtime. Other QAIRT versions produce context binaries / ABI the
shipped runtime rejects. Without these libs, any Genie pipeline
crashes at first use with
`dlopen failed: library "libQnnGenAiTransformer.so" not found`.

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
2. **Load** — `start_model(model_name:, engines_path:)`. First hit
   downloads the HF revision for this SDK line into the app's internal
   files dir (not on external storage, excluded from user-visible media).
3. **Infer** — batch `infer` or streaming `infer_stream` / the TTS
   streamer (`send` → `finish_stream`).
4. **Stop** — `stop_model(model_name:)` to free the engine's memory.

### Revisions

Omit `revision` in normal apps. The SDK resolves each HF repo's default
branch (`android` / `main` / `develop`) via an internal map — some
models track their `main` branch, others a dedicated `android` or
`develop` branch. Override by passing an explicit `revision`, which may
be a branch or a version tag.

### Init & seats (product)

- A seat is `(api_token, device)` — see [licensing.md](./docs/licensing.md).
- Pricing / plans: [app.thestage.ai](https://app.thestage.ai).
- Do not document or depend on how the device identity is derived.

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

Subscribe to `TheStageFlutterSDK.on_progress` (Flutter). Phases are
monotonic over `0…1`:

| Phase | Band | Notes |
| --- | --- | --- |
| `downloading` | 0.00 – 0.70 | HF fetch (skipped on cache hit) |
| `extracting` | 0.70 – 0.85 | unpack (skipped on cache hit) |
| `loading` | 0.85 – 0.99 | pipeline construction |
| `ready` | 1.00 | success only |

### Flutter ↔ native parity

| Operation | Native (Kotlin) | Flutter (Dart) |
| --- | --- | --- |
| Register context | `TheStageAI.registerContext(ctx)` | (automatic) |
| Initialize | `TheStageAI.initialize(api_token = …)` | `TheStageFlutterSDK.initialize(api_token: …)` |
| Start | `TheStageAI.start_model(...)` | `start_model(...)` |
| Stop | `TheStageAI.stop_model(model_name = …)` | `stop_model(model_name: …)` |
| Batch | `TheStageAI.infer(model_name, input_json)` | `infer(...)` |
| Stream | `TheStageAI.infer_stream(...)` → `Flow` | `infer_stream(...)` → `Stream` |
| TTS push | streamer `send` / `finish_stream` / `stop_stream` | `send` / `finish_stream` / `stop_stream` |
| Progress | — | global `on_progress` |

Both surfaces use the same `model_name` strings and the same
`input_json` shape; the Flutter path is JSON-only.

---

## Documentation map

| Doc | Open when you need… |
| --- | --- |
| [llm.md](./docs/llm.md) | Chat, streaming tokens, sampling, KV |
| [whisper.md](./docs/whisper.md) | ASR, VAD chunking, languages |
| [vlm.md](./docs/vlm.md) | On-device image + prompt → text |
| [tts.md](./docs/tts.md) | NeuTTS voices + streaming (and the nano / espeak path) |
| [vad.md](./docs/vad.md) | Silero chunk contract |
| [streaming.md](./docs/streaming.md) | Back-pressure, sentence segmentation |
| [voice_agent.md](./docs/voice_agent.md) | Full loop, barge-in, smart-turn knobs |
| [speaker_embedding.md](./docs/speaker_embedding.md) | Enroll / verify |
| [model_management.md](./docs/model_management.md) | Availability checks, offloading |
| [ai_packs.md](./docs/ai_packs.md) | Ship models via Google Play AI packs |
| [licensing.md](./docs/licensing.md) | Token, seats, offline rules |
| [logging.md](./docs/logging.md) | Support breadcrumbs |
| [product_terms.md](./docs/product_terms.md) | Commercial / legal pointer |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `Token validation failed` at first start | Missing / bad token, or offline on first run | Pass a valid token; be online for the one-time check |
| `dlopen failed: … libQnnGenAiTransformer.so not found` | Genie pipeline without the QAIRT libs | Copy the four QAIRT 2.42 libs — see [QAIRT runtime libs](#qualcomm-qairt-runtime-libs-genie-backend) |
| `Could not create context from binary … err 5000` | QAIRT version mismatch | Use QAIRT **2.42.0**; other versions are rejected |
| FastRPC / NPU skel won't load in a native app | `.so` compressed in the APK | Set `android:extractNativeLibs="true"` |
| Duplicate `.so` at merge | ORT + core ship the same lib | Add the `jniLibs.pickFirsts` block above |
| First infer very slow | HF download | Wait for `ready`; later runs use the cache |
| Flutter audio glitches / NaNs | `Float64List` or wrong rate | Use `Float32List`; match the audio table above |
| Flutter git dependency won't resolve | Floating ref | Pin `ref: v1.0.0` |

---

## Secrets

The Flutter example apps read tokens at build time via
`String.fromEnvironment(...)` and `--dart-define-from-file=secrets.json`.
Each ships a `secrets.example.json` template — copy it to `secrets.json`
and fill in your keys. `secrets.json` is covered by `.gitignore`; real
keys never belong in source.

## License

See [LICENSE](LICENSE).

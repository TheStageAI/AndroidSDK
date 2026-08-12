# tts_front_stream

Streaming neural TTS demo. Type some text, hit play, and audio chunks
start streaming back from the device while the rest of the sentence is
still being generated — all on the Snapdragon NPU.

## What it exercises

- `TheStageFlutterSDK.initialize(api_token:)`
- `TheStageFlutterSDK.start_model(model_name: 'neutts', …)` with
  HuggingFace engine prefetch.
- `TheStageFlutterSDK.infer_stream(...)` in push mode (per-chunk audio
  events).
- `TheStageAudioPlayer` for low-latency playback.

## Prerequisites

- A TheStage API token — set as `TS_API_TOKEN` in `secrets.json`.
- A physical Qualcomm Snapdragon device (arm64-v8a), Android 9+
  (minSdk 28).
- A Flutter toolchain (`flutter --version`).

## Run

```bash
# from the repo root
./scripts/setup.sh    # one-time, idempotent

cp examples/tts_front_stream/secrets.example.json \
   examples/tts_front_stream/secrets.json
$EDITOR examples/tts_front_stream/secrets.json
```

Then:

```bash
cd examples/tts_front_stream
flutter pub get
flutter run --release \
    --dart-define-from-file=secrets.json \
    -d <YOUR_DEVICE_ID>
```

Use `flutter devices` to find the device id.

## Notes

- The first launch downloads the NeuTTS engines from HuggingFace
  (~hundreds of MB) and caches them in app storage. Subsequent launches
  start instantly.
- Audio plays as 24 kHz mono float PCM.
- The NPU backend is Snapdragon-only; the app falls back to GPU/CPU on
  unsupported hardware.

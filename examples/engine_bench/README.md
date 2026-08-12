# engine_bench

On-device **engine benchmark** app: measure each shipping engine's
throughput and latency on your device and export the session as JSON.
All engines load from Hugging Face on first use — no model weights are
bundled.

## What it measures

Four tabs, each with a streaming **Generate** and a warmup + N-run
**Benchmark**:

- **TTS** — NeuTTS (`neutts-nano-multilingual`): first-audio latency,
  real-time factor, decode tok/s.
- **ASR** — Whisper (`thewhisper-large-v3-turbo`): record from the mic →
  transcribe; real-time-factor-x, encoder ms, decode tok/s.
- **VLM** — LFM2-VL (`LFM2.5-VL-450M`): pick an image → caption; TTFT and
  decode tok/s.
- **LLM** — greyed out for now: there is no published on-device
  chat-LLM bundle for Android yet. The bench code is retained and
  re-enables automatically once one ships.

The **Share** action in the app bar exports the whole session (device id
+ per-run metrics) as a JSON file through the system share sheet.

## Prerequisites

- A TheStage API token — set as `TS_API_TOKEN` in `secrets.json`.
- A physical Qualcomm Snapdragon device (arm64-v8a), Android 9+
  (minSdk 28). Microphone and photo-access permissions are requested at
  use (for ASR and VLM).
- Space + a good connection for the first-run model downloads (each
  engine caches after the first load).

## Run

```bash
# from the repo root
./scripts/setup.sh    # one-time, idempotent

cp examples/engine_bench/secrets.example.json \
   examples/engine_bench/secrets.json
$EDITOR examples/engine_bench/secrets.json
```

Then:

```bash
cd examples/engine_bench
flutter pub get
flutter run --release \
    --dart-define-from-file=secrets.json \
    -d <YOUR_DEVICE_ID>
```

## Notes

- Numbers are steady-state medians over N runs (after warmup) — the first
  run of any tab also pays the one-time model download + compile.
- The heavy inference runs natively in the SDK, so the figures reflect
  on-device engine performance, not Flutter overhead.

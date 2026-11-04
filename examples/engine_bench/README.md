# engine_bench

On-device **engine benchmark** app: measure each shipping engine's
throughput and latency on your device and export the session as JSON.
All engines load from Hugging Face on first use — no model weights are
bundled.

## What it measures

Four tabs, in the app's order, each with a streaming **Generate** and a
warmup + N-run **Benchmark**:

- **LLM** — the on-device LLMs (LFM2.5, LFM3, Qwen3.5): TTFT and decode
  tok/s, thinking off. An MTP switch appears for models with a drafter;
  a run with it is recorded as `<model> + MTP`.
- **TTS** — NeuTTS (`neutts-nano-multilingual`): first-audio latency,
  real-time factor, decode tok/s. The voice chips list the loaded
  bundle's own voices.
- **ASR** — Whisper (`thewhisper-large-v3-turbo`): record from the mic →
  transcribe; real-time-factor-x, encoder ms, decode tok/s. Benchmark
  replays the last recorded clip.
- **VLM** — LFM2.5-VL (`LFM2.5-VL-450M`, `LFM2.5-VL-1.6B`) and Gemma 4
  E2B: pick an image → caption; TTFT and decode tok/s.

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
./scripts/setup.sh    # one-time, idempotent; creates examples/*/secrets.json

$EDITOR examples/engine_bench/secrets.json    # the file setup.sh created

cd examples/engine_bench
flutter pub get
flutter run --release \
    --dart-define-from-file=secrets.json \
    -d <YOUR_DEVICE_ID>
```

Without a token the app opens on a "TS_API_TOKEN not set" screen: put
the token in `secrets.json` and run again.

### Build-time options

Each is a `--dart-define=NAME=value`. Leave the revisions empty to get
the SDK-pinned commit of each repo.

| Define | Default | What it changes |
|---|---|---|
| `LLM_REVISION` | empty | Revision for every LLM repo |
| `TTS_ENGINE_PATH` | `TheStageAI/neutts-nano-multilingual` | TTS repo id or local bundle path |
| `TTS_REVISION` | empty | TTS revision |
| `WHISPER_ENGINE_PATH` | `TheStageAI/thewhisper-large-v3-turbo` | ASR repo id or local bundle path |
| `WHISPER_REVISION` | empty | ASR revision |
| `LFM2_VL_ENGINES_PATH` | empty | Adds a "Custom bundle" VLM (repo id or local path) to the picker |
| `LFM2_VL_REVISION` | empty | Revision for every VLM repo |

## Notes

- Numbers are steady-state medians over N runs (after warmup) — the first
  run of any tab also pays the one-time model download + compile.
- The heavy inference runs natively in the SDK, so the figures reflect
  on-device engine performance, not Flutter overhead.

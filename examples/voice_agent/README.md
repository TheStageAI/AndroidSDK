# voice_agent

Full voice-assistant demo: speak into the mic, get a spoken response
back, all orchestrated natively and on-device by default: Whisper STT,
an on-device LLM (`TheStageAI/LFM2.5-350M`; others in the pickers),
and TTS streaming back through NeuTTS (`neutts-nano-multilingual`).

## What it exercises

- Mic capture + on-device VAD + Whisper STT, with live caption partials
  and smart-turn end-of-turn detection.
- The on-device LLM (`llm_provider: local`, run with thinking off), or a
  cloud provider (OpenAI-compatible) reached over HTTPS — pick it in
  Settings, or change the LLM fields in
  `lib/backend/settings_model.dart`.
- Tool calling: the on-device LLM calls tools mid-reply (`llm_tools`,
  default `voice`: weather, local time, web search, Wikipedia, a
  calculator and phone actions; `web` keeps only weather, time and
  search). The status line shows
  `Calling tool...` and each call and result appears as a small
  monospace line in the chat; only the answer is spoken.
- Streaming NeuTTS playback with barge-in: speak over the reply to
  interrupt it.
- The native voice-agent orchestrator through `TSVoiceAgent`: the
  `agent.events` stream (state changes, transcripts, reply deltas,
  errors, the TTS bundle's `voices`), the `tts_levels` stream that
  drives the speaking meter, and the `capabilities` map `start()`
  returns.

## How the code is laid out

The app is deliberately split so the data flow is easy to follow:

- `lib/backend/voice_agent_controller.dart` — the single place that
  subscribes to `agent.events` / `tts_levels` and turns each event into
  typed UI state. **Start here to see how transcription and LLM output
  reach the screen.**
- `lib/ui/voice_chat_screen.dart` — a "dumb" view: it renders the
  controller's fields and wires the Start / Stop / Interrupt buttons.
- `lib/backend/settings_model.dart` — model ids, LLM provider config,
  and the interruption / VAD / turn-detection knobs sent to
  `agent.start(config:)`.

## Prerequisites

- A TheStage API token — set as `TS_API_TOKEN` in `secrets.json`.
- Optional: an OpenAI API key — set as `OPENAI_API_KEY` in
  `secrets.json` — only for the cloud LLM provider.
- A physical Qualcomm Snapdragon device (arm64-v8a), Android 9+
  (minSdk 28). Microphone permission is requested at launch.

## Run

```bash
# from the repo root
./scripts/setup.sh    # one-time, idempotent; creates examples/*/secrets.json

$EDITOR examples/voice_agent/secrets.json    # the file setup.sh created

cd examples/voice_agent
flutter pub get
flutter run --release \
    --dart-define-from-file=secrets.json \
    -d <YOUR_DEVICE_ID>
```

Pick the models in the bar above the controls, then tap **Start**. The
first start downloads and prepares every model; the status line shows
which one is loading. The agent then listens continuously: speak, and it
answers.

## Notes

- **Start** / **Stop** run and tear down the whole agent; the model and
  voice pickers are editable only while it is stopped. **Interrupt**
  appears while the agent is thinking or speaking and cancels the reply.
  A failed start shows its error in the banner and returns to idle.
- The voice picker lists the loaded TTS bundle's own voices once the
  agent has started (a short default list before that).
- Settings holds the VAD, turn-detection, barge-in and AEC knobs; they
  apply at the next Start (the interrupt knobs also apply live).
- A city name or search query you ask about is sent to Open-Meteo,
  DuckDuckGo or Wikipedia; set Tools to `none` in Settings to keep
  every request on the phone. The `voice` and `phone` presets open
  other apps (dialer, maps, SMS) for you to confirm.
- With the default on-device LLM, everything runs on the phone after
  the first model downloads; the cloud provider adds one network hop
  per reply.

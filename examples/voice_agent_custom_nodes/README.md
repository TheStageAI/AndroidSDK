# voice_agent_custom_nodes

The `voice_agent` demo plus **custom voice-agent nodes**: host-owned
nodes attached to the running agent graph via `extra_nodes`, an ephemeral
on-device VLM that captions images in quiet states, a typed-turn box, and
a screen recorder for capturing demos.

## What it exercises

- **`extra_nodes`** — attach your own `TSAgentNode`s to the native
  agent graph. An `EventLogNode` mirrors the internal event bus; a
  `VLMCaptionNode` captions a picked image with LFM2.5-VL 450M or
  Gemma 4 E2B (picked in the Custom Nodes panel).
- **`AgentNodeContext`** — a node's ports (`sendPort` / `recvPort`) and
  bus injection (`publishEvent`); the app-level `send_request` submits a
  typed user turn that drives the same LLM → TTS path as speech.
- **Model residency** — a host-side `ModelRoster` starts the VLM for the
  caption burst and stops it afterwards, so heavy vision work only runs
  in a quiet agent state and never fights STT / LLM / TTS.
- **Screen recording** — `TSScreenRecorder` captures the screen
  plus a mic + assistant audio mix to the gallery, for demo clips.

## How the code is laid out

- `lib/backend/voice_agent_controller.dart` — owns the agent, the two
  custom nodes and the roster; **start here** to see how nodes attach and
  how bus events reach the UI.
- `lib/nodes/{event_log_node,vlm_caption_node}.dart` — app-local node
  recipes. Copy them into your own host as a starting point.
- `lib/backend/model_roster.dart` — the resident / ephemeral residency
  helper (reuses `start_model` / `stop_model` / `prefetch_model`).
- `lib/ui/custom_nodes_screen.dart` — the panel wiring the typed turn,
  VLM caption, event log and record button.

## Prerequisites

- A TheStage API token — set as `TS_API_TOKEN` in `secrets.json`.
- Optional: an OpenAI API key — set as `OPENAI_API_KEY` in
  `secrets.json` — only for the cloud LLM provider. The default LLM runs
  on-device (`TheStageAI/LFM2.5-350M`).
- A physical Qualcomm Snapdragon device (arm64-v8a), Android 9+
  (minSdk 28). Microphone (and, for the recorder, screen-capture)
  permission is requested at use.

## Run

```bash
# from the repo root
./scripts/setup.sh    # one-time, idempotent; creates examples/*/secrets.json

$EDITOR examples/voice_agent_custom_nodes/secrets.json    # the file setup.sh created

cd examples/voice_agent_custom_nodes
flutter pub get
flutter run --release \
    --dart-define-from-file=secrets.json \
    -d <YOUR_DEVICE_ID>
```

Tap **Start** on the chat screen, then open the Custom Nodes panel (the
hub icon in the app bar) for the typed turn, VLM caption, screen
recorder and event log.

## Notes

- Custom nodes see the **internal** event bus (UPPERCASE kinds such as
  `USER_REQUEST`, `STATE`, `BARGE_IN`) via `onEvent` — distinct from the
  public snake_case `agent.events`. See `docs/voice_agent.md`.
- VLM captions only drain in quiet states (`idle` / `sleeping` /
  `listening`); the roster starts the VLM for the burst and stops it
  afterwards. Stopping the agent mid-caption waits for that caption to
  finish before the node is torn down.
  `thinking`, `tool_calling` and `speaking` are active states.
- The on-device LLM gets the SDK's built-in `voice` tools (the config
  sends no `llm_tools`); a tool call shows as `Calling tool...`.
- The screen recorder mixes mic (left) and assistant TTS (right) into a
  stereo track so a recorded demo carries both sides of the conversation.

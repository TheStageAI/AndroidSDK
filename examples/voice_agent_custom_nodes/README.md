# voice_agent_custom_nodes

The `voice_agent` demo plus **custom voice-agent nodes**: host-owned
nodes attached to the running agent graph via `extraNodes`, an ephemeral
on-device VLM that captions images in quiet states, a typed-turn box, and
a screen recorder for capturing demos.

## What it exercises

- **`extraNodes`** — attach your own `TheStageAgentNode`s to the native
  agent graph. An `EventLogNode` mirrors the internal event bus; a
  `VLMCaptionNode` runs LFM2-VL on a picked image.
- **`AgentNodeContext`** — a node's ports (`sendPort` / `recvPort`) and
  bus injection (`publishEvent`); the app-level `sendRequest` submits a
  typed user turn that drives the same LLM → TTS path as speech.
- **Model residency** — a host-side `ModelRoster` starts the VLM for the
  caption burst and stops it afterwards, so heavy vision work only runs
  in a quiet agent state and never fights STT / LLM / TTS.
- **Screen recording** — `TheStageScreenRecorder` captures the screen
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
- An OpenAI API key — set as `OPENAI_API_KEY` in `secrets.json` (optional;
  only the cloud-LLM replies need it — the custom-node, VLM-caption and
  screen-recorder demos run without it).
- A physical Qualcomm Snapdragon device (arm64-v8a), Android 9+
  (minSdk 28). Microphone (and, for the recorder, screen-capture)
  permission is requested at use.

## Run

```bash
# from the repo root
./scripts/setup.sh    # one-time, idempotent

cp examples/voice_agent_custom_nodes/secrets.example.json \
   examples/voice_agent_custom_nodes/secrets.json
$EDITOR examples/voice_agent_custom_nodes/secrets.json
```

Then:

```bash
cd examples/voice_agent_custom_nodes
flutter pub get
flutter run --release \
    --dart-define-from-file=secrets.json \
    -d <YOUR_DEVICE_ID>
```

## Notes

- Custom nodes see the **internal** event bus (UPPERCASE kinds such as
  `USER_REQUEST`, `STATE`, `BARGE_IN`) via `onEvent` — distinct from the
  public snake_case `agent.events`. See `docs/voice_agent.md`.
- VLM captions only drain in quiet states (`idle` / `sleeping` /
  `listening`); the roster parks the model around the burst.
- The screen recorder mixes mic (left) and assistant TTS (right) into a
  stereo track so a recorded demo carries both sides of the conversation.

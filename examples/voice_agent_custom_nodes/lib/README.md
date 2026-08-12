# Voice Agent — Custom Nodes app — architecture

A deliberately small, clearly layered Flutter front-end for the on-device
voice agent, extended with **custom host nodes**. The native SDK
(`thestage_android_sdk`) runs the whole pipeline (mic → VAD → ASR → LLM →
TTS → speaker); this app **configures it**, **subscribes to its events**,
**draws the conversation**, and **attaches its own Dart nodes** to the
native graph.

## Layers

```
lib/
  main.dart                         App entry: init SDK, gate on secrets.
  models/
    chat_message.dart               Plain data: ChatMessage + MessageRole.
  nodes/                            App-local custom nodes (extraNodes recipes).
    event_log_node.dart             Mirrors the internal bus via onEvent.
    vlm_caption_node.dart           Captions an image (ephemeral lfm2-vl).
  backend/                          Everything that talks to the SDK.
    voice_agent_controller.dart     THE bridge: events → typed state + commands,
                                    owns the nodes, roster, captionImage/sendText.
    model_roster.dart               Residency helper: resident/warmDisk/ephemeral,
                                    ensureHot/release/withEphemeral(Swap).
    settings_model.dart             User knobs + toConfig() (LLM/ASR/TTS wiring).
  ui/                               Pure rendering. Never touches the SDK.
    voice_chat_screen.dart          Composition: owns controller, wires buttons.
    custom_nodes_screen.dart        Event log + VLM caption + sendRequest + record.
    settings_screen.dart            Settings form bound to VoiceAgentSettings.
    widgets/
      transcript_area.dart          Chat list + startup model checklist.
      chat_bubble.dart              One bubble (user right / assistant left).
      bottom_bar.dart               Status line, mic meter, Start/Stop/Interrupt.
      error_banner.dart             Dismissible error strip.
      agent_status.dart             State → colour / label helpers.
```

**Rule of thumb:** if it imports `thestage_android_sdk` it lives in
`backend/` or `nodes/` (plus the screens, which own the controller). UI
widgets only import `models/` and `backend/` types — never the SDK
directly.

## Custom nodes

The two nodes under `nodes/` are attached at `agent.start(extraNodes: […])`
in `VoiceAgentController.start`:

- **`EventLogNode`** (`runWhen: []`, always gated open) — every bus event
  is forwarded through `onEvent` into `controller.busEvents`, which the
  Custom Nodes screen renders as a live log.
- **`VLMCaptionNode`** (`runWhen: [idle, sleeping, listening]`) — a
  host-owned (`external` lifecycle) captioner. `controller.captionImage`
  waits for a quiet agent state, then runs the model through the
  `ModelRoster` as an **ephemeral** `lfm2-vl` handle (start → caption →
  stop) and pushes the caption on the `vlm.caption` port.

`ModelRoster` keeps `resident` / `warmDisk` / `ephemeral` slots for API
parity; on Android the agent owns VAD/STT/TTS internally, so the roster is
used here only to bracket the VLM burst.

## Data flow

```
                 ┌─────────────── BACKEND (talks to SDK) ───────────────┐
  mic / wake ──► VoiceAgent (native) ──► agent.events  ──► VoiceAgentController
                                          on_progress         (event → typed state)
                 settings.toConfig() ───► agent.start(config)    │
                 └──────────────────────────────────────────────┼────────┘
                                                                 │ ChangeNotifier
                 ┌──────────────── FRONTEND (renders state) ─────▼────────┐
                 VoiceChatScreen → TranscriptArea / BottomBar / ...
                 └────────────────────────────────────────────────────────┘
```

### How bubbles connect to ASR and the LLM

Both flows are **two events**: the first feeds a *live* bubble, the second
*finalizes* it into a permanent line. All of this mapping happens in one place,
`VoiceAgentController._onEvent`.

| Source | Event (`kind`) | Controller field | Bubble |
| ------ | -------------- | ---------------- | ------ |
| ASR    | `user_request_partial` | `partialTranscript` | live USER bubble (right) |
| ASR    | `user_request`         | `messages` (user)   | final USER bubble |
| LLM    | `response_delta`       | `streamingResponse` | live ASSISTANT bubble (left) |
| LLM    | `response_done`        | `messages` (asst)   | final ASSISTANT bubble |

`TranscriptArea` draws `messages` first, then appends the live partial (user)
and the live stream (assistant) so the newest content is always at the bottom.

### How we subscribe to events

`VoiceAgentController` is the only subscriber. In its constructor it listens to:

- `agent.events` → `_onEvent` (conversation + pipeline events, table above),
- `TheStageFlutterSDK.on_progress` → `_onProgress` (model download/extract/
  compile progress for the startup checklist).

Both subscriptions are cancelled in `dispose()`. The controller is a
`ChangeNotifier`; the screen wraps the tree in a single `AnimatedBuilder` so any
state change repaints the relevant bubbles.

### How the LLM / ASR are configured

`VoiceAgentSettings.toConfig()` builds the `config` map passed to
`agent.start(config:)`. It's grouped by subsystem:

- **LLM** — `llm_provider` / `llm_model` / `llm_endpoint` / `llm_api_key` /
  `system_prompt` / `max_tokens` / `temperature`.
- **ASR** — `stt` (Whisper), `stt_language`, `asr_streaming` (live captions),
  plus the `turn_*` keys for neural (smart-turn) end-of-turn detection.
- **TTS** — `tts` (NeuTTS), `tts_voice`.

The `turn_detector` engines repo is injected at `start()` time in
`voice_chat_screen.dart` as `TheStageAI/smart-turn-v3` — the SDK downloads
and caches it from HuggingFace on first run, like the other engines.

# Voice Agent

End-to-end on-device voice assistant: VAD → STT → LLM → TTS, with
neural end-of-turn detection (the **smart-turn-v3** model), interruption
handling, streaming transcription (live partial captions), and
sentence-level streaming for sub-second time-to-first-audio.

The agent is implemented as a small actor-based **node graph**.
`TheStageVoiceAgent` is a thin builder that wires the nodes and bridges
the internal event bus onto a public `events: Flow<TheStageAgentEvent>`
plus a few typed output channels (LLM deltas, transcripts, VAD
probability).

## Quick Start (Kotlin)

```kotlin
// build.gradle.kts: implementation(files("libs/TheStageCore.aar"))
import ai.thestage.qlip.TheStageAI
import ai.thestage.qlip.voice_agent.TheStageVoiceAgent
import ai.thestage.qlip.voice_agent.TheStageAgentConfig
import ai.thestage.qlip.voice_agent.TheStageAgentEvent

// Inside a coroutine scope.
TheStageAI.registerContext(context)
TheStageAI.initialize(api_token = "your-api-token")

val config = TheStageAgentConfig(
    vad = "TheStageAI/silero-vad",
    stt = "TheStageAI/thewhisper-large-v3-turbo",
    tts = "TheStageAI/neutts-multilingual",
    llm_provider = "openai_compatible",
    llm_endpoint = "https://api.openai.com/v1/chat/completions",
    llm_api_key = "sk-...",
    llm_model = "gpt-4o-mini",
    system_prompt = "You are a helpful voice assistant. Keep replies short."
)

val agent = TheStageVoiceAgent(config)

// Legacy event stream (state changes, transcripts, deltas, errors).
launch {
    agent.events.collect { event ->
        when (event.kind) {
            TheStageAgentEvent.Kind.STATE_CHANGED ->
                println("[STATE] ${event.data["state"]}")
            TheStageAgentEvent.Kind.USER_REQUEST ->
                println("[YOU] ${event.data["text"]}")
            TheStageAgentEvent.Kind.RESPONSE_DELTA ->
                print(event.data["delta"])
            TheStageAgentEvent.Kind.RESPONSE_DONE ->
                println("\n[ASSISTANT DONE]")
            TheStageAgentEvent.Kind.ERROR ->
                println("[ERROR] ${event.data["message"]}")
            else -> {}
        }
    }
}

// Typed channels: each is a plain Kotlin Flow you can collect
// independently.
launch {
    agent.llm_deltas.collect { delta ->
        // Append delta to a chat bubble, etc.
    }
}

agent.start()
// agent runs continuously — speak into the mic
```

For a fully on-device assistant, set `llm_provider = "local"` and point
`llm` at an on-device LLM bundle (e.g. `"TheStageAI/Qwen3-0.6B"` or
`"TheStageAI/LFM2.5-230M"`).

## Quick Start (Flutter)

```dart
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');

final agent = TheStageVoiceAgentFlutter();

agent.events.listen((event) {
  switch (event['kind']) {
    case 'state_changed': print('STATE: ${event['state']}');
    case 'user_request':  print('YOU: ${event['text']}');
    case 'response_delta': stdout.write(event['delta']);
    case 'response_done': print('\nASSISTANT DONE');
  }
});

// Typed broadcast streams (one EventChannel each).
agent.llmDeltas.listen((delta) => /* update assistant bubble */);
agent.transcripts.listen((text) => /* show user turn */);
agent.vadProbabilities.listen((p) => /* drive a level meter */);

await agent.start(config: {
  'vad': 'TheStageAI/silero-vad',
  'stt': 'TheStageAI/thewhisper-large-v3-turbo',
  'tts': 'TheStageAI/neutts-multilingual',
  'llm_provider': 'openai_compatible',
  'llm_endpoint': 'https://api.openai.com/v1/chat/completions',
  'llm_api_key': 'sk-...',
  'llm_model': 'gpt-4o-mini',
  'system_prompt': 'You are a helpful voice assistant.',
});

// Later:
await agent.interrupt();          // stop current response
await agent.say('Welcome back!'); // speak arbitrary text (skips LLM)
await agent.updateInterruptConfig(interruptMinSpeechMs: 200);
await agent.stop();
```

## Deferred Mic (`auto_listen`)

By default the agent opens the microphone and starts scanning for
speech as soon as `start()` finishes loading models
(`auto_listen = true`). When you want to load the models but **hold the
mic closed** — e.g. to finish downloading a heavy on-device LLM, or to
show a "tap to talk" affordance before capturing any audio — start with
`auto_listen = false` and open the mic yourself with `begin_listening()`
once you're ready.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `auto_listen` | Boolean | `true` | `true`: open the mic immediately after models load. `false`: load models but leave the mic closed until `begin_listening()`. |

`begin_listening()` is idempotent (a no-op once the agent is already
listening), so it is safe to call more than once.

**Kotlin:**

```kotlin
val agent = TheStageVoiceAgent(config.copy(auto_listen = false))
agent.start()                // models load; mic stays closed
// ... finish any deferred setup (download local LLM, show UI) ...
agent.begin_listening()      // open the mic + start scanning
```

**Flutter:**

```dart
await agent.start(config: {
  ...,
  'auto_listen': false,      // load models, keep mic closed
});
// ... later, when ready:
await agent.beginListening();
```

## State Machine

```
                     ┌────────────────────────────────────────┐
                     │  if config.wake_word == null           │
idle → loading ─────►│  listening ⇄ thinking → speaking       │──► listening
                     │                                        │
                     │  else (wake-word configured)           │
                     │  sleeping ─WW─► listening ⇄ thinking   │──► speaking ──► sleeping
                     └────────────────────────────────────────┘
```

| State | Meaning |
|-------|---------|
| `idle` | Models not loaded |
| `loading` | Models being downloaded / loaded |
| `sleeping` | Wake-word standby. VAD/WW are live, ASR/LLM/TTS are gated off. Only entered when `wake_word` is configured. |
| `listening` | Mic open, VAD scanning for speech |
| `thinking` | Speech committed, LLM is generating |
| `speaking` | TTS streaming audio to the speaker |

State is derived inside the orchestrator from the event stream and is
the only place the state machine lives. It is broadcast as a
`state_changed` event and also exposed as `agent.state`
(`StateFlow<TheStageAgentState>`).

## Public Output Channels

In addition to the legacy `events` stream, the agent exposes typed
fan-out ports as plain Kotlin `Flow`s. Each collector sees every value
— perfect for plugging UI widgets, log taps and speech-to-file
recorders side-by-side without intermediate bookkeeping.

| Property | Type | What it carries |
|----------|------|-----------------|
| `agent.llm_deltas` | `Flow<String>` | Each LLM token delta as it is generated, in order |
| `agent.transcripts` | `Flow<String>` | One value per user turn (the finalized Whisper transcript; empty on aborted turns) |
| `agent.vad_probabilities` | `Flow<Double>` | Per-frame Silero probability ([0, 1]); roughly one value every 32 ms |
| `agent.state` | `StateFlow<TheStageAgentState>` | Current lifecycle state |

Stable partial captions (committed-so-far text while the user speaks)
are surfaced on the `events` stream as `user_request_partial` events
when `asr_streaming` is on — great for live captions. They never feed
the LLM.

```kotlin
val tap = launch {
    agent.vad_probabilities.collect { prob ->
        // update a level meter on the main thread
    }
}
// ...later
tap.cancel()
```

The same channels are exposed in Flutter as `agent.llmDeltas`
(`Stream<String>`), `agent.transcripts` (`Stream<String>`), and
`agent.vadProbabilities` (`Stream<double>`), each backed by its own
`EventChannel`.

## Configuration

### Models

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `vad` | String | required | HF id or local path of Silero VAD bundle |
| `stt` | String | required | HF id or local path of Whisper bundle |
| `tts` | String? | `null` | HF id or local path of NeuTTS bundle (required to speak) |
| `tts_voice` | String | `"paul"` | Voice preset id |
| `wake_word` | String? | `null` | Optional wake-word bundle. When set, the agent rests in `sleeping` until the wake word fires. |
| `stt_language` | String | `"en"` | Whisper decode language (ISO-639-1, e.g. `"en"`, `"es"`) |
| `stt_revision` | String | `"android"` | HF branch / tag for STT |
| `tts_revision` | String | `"android"` | HF branch / tag for TTS |
| `component_offload` | Boolean | `false` | Android memory optimization: swap STT (whisper) and the TTS-LLM in/out of memory across listening/speaking so they never co-reside. Default off = always-loaded. |

### Compute device routing (Snapdragon NPU)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `vad_device` | String | `"npu"` | Silero VAD compute device |
| `stt_device` | String | `"npu"` | Whisper coarse default |
| `stt_devices` | `Map<String,String>?` | `null` | Per-module override: `mel`, `encoder`, `decoder` |
| `tts_device` | String | `"npu"` | NeuTTS coarse default |
| `tts_devices` | `Map<String,String>?` | `null` | Per-module override: `llm`, `neucodec` |
| `ww_device` | String | `"npu"` | Wake-word compute device |

The Qualcomm Snapdragon NPU (Hexagon/HTP via QNN) is the default for
the heavy graphs (Whisper encoder/decoder, the NeuTTS LLM) because it
runs the fixed-shape compiled context binaries efficiently and keeps
running when the app is in the background (with a foreground service).
GPU and CPU are fallbacks. Small stateful models (Silero VAD, the
smart-turn classifier) run on ORT-CPU regardless — they don't benefit
from the NPU. Some sub-modules are pinned per the bundle's
`metadata.json` (e.g. the Whisper mel front-end stays on CPU).

### LLM

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `llm_provider` | String | `"local"` | `"local"` (on-device SDK model) or `"openai_compatible"` (remote SSE chat-completions) |
| `llm` | String? | `null` | Local: engines path of the on-device LLM |
| `llm_model` | String | `"gpt-4o-mini"` | Remote model id |
| `llm_endpoint` | String | OpenAI chat-completions | Remote endpoint URL |
| `llm_api_key` | String | `""` | Remote API key |
| `llm_provider_override` | `LlmProvider?` | `null` | Inject a custom / mock provider (overrides the above) |
| `system_prompt` | String | helpful default | Prepended as a system message |
| `max_tokens` | Int | 256 | Generation cap |
| `temperature` | Double | 0.7 | Sampling temperature |
| `chat_memory` | `ChatMemory` | `SlidingWindowMemory(max_turns = 10)` | History strategy |

### VAD / endpointing

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `vad_threshold` | Double | 0.8 | Speech probability threshold |
| `vad_onset_ms` | Int | 96 | Sustained voiced duration to trigger onset |
| `silence_timeout_ms` | Int | 600 | Trailing silence to commit turn |
| `max_accumulation_ms` | Int | 30000 | Hard cap on a single turn |
| `pre_roll_ms` | Int | 200 | Pre-roll captured before onset |

All durations are in **milliseconds**; the nodes convert them to the live VAD
frame cadence (`frame_samples / sample_rate`, ≈32 ms for Silero @ 16 kHz)
internally. `silence_timeout_ms` only applies to the default VAD endpointer
(`turn_detection_mode == "vad"`); the DNN endpointer ignores it.

### Turn detection (end-of-turn)

The endpointer is pluggable. `"vad"` (default) commits a turn after a
fixed silence gap (`silence_timeout_ms`). `"dnn"` replaces that with the
pipecat **smart-turn-v3** model: at each pause it runs a learned
end-of-turn check on the trailing waveform, so the agent waits through
mid-sentence pauses but responds quickly once you're actually done.
`"none"` never fires end-of-turn (continuous transcription).

VAD is the cheap gate (onset + pause detection); the DNN is the expensive
semantic check run **single-flight, off-thread, only at pauses**, with a hard
`turn_max_silence_ms` floor so it can never hang or classify an empty
window. The model sees the **continuous** waveform from onset (incl. pre-roll)
through the pause — never VAD-filtered audio.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `turn_detection_mode` | String | `"vad"` | `"vad"` (silence timeout), `"dnn"` (smart-turn model), or `"none"` |
| `turn_detector` | String | `"TheStageAI/smart-turn-v3"` | smart-turn engines repo/path (used only for `"dnn"`) |
| `turn_detector_revision` | String | `"main"` | HF branch / tag for the smart-turn engines |
| `turn_detector_device` | String | `"cpu"` | Compute device for the classifier (ORT-CPU on Android) |
| `turn_eot_threshold` | Double | 0.85 | Completion prob at/above which a checkpoint counts as "done" |
| `turn_eot_confirm_count` | Int | 2 | Consecutive "done" verdicts required before committing. Debounces a single spike on a mid-sentence pause. `1` = fire on first positive. |
| `turn_eot_high_confidence` | Double | 1.0 | Verdict prob that commits immediately, skipping confirmation. `>= 1.0` (default) disables the bypass (see note). |
| `turn_pause_trigger_ms` | Int | 256 | Trailing silence before the first model call |
| `turn_reeval_interval_ms` | Int | 120 | Re-run cadence on a sustained pause (0 disables) |
| `turn_max_silence_ms` | Int | 5000 | Hard fallback; MUST be < `turn_window_ms` |
| `turn_window_ms` | Int | 8000 | Trailing audio window fed to the model |
| `turn_min_speech_ms` | Int | 250 | Minimum voiced speech before the model is consulted |
| `turn_asr_silence_hangover_ms` | Int | 200 | Trailing silence still fed to streaming ASR after speech stops (bounds "mm"/"?" filler; the turn model still sees the full pause) |

```kotlin
val config = TheStageAgentConfig(
    vad = ..., stt = ..., tts = ..., llm_provider = "local", llm = ...,
    turn_detection_mode = "dnn",
    turn_detector = "TheStageAI/smart-turn-v3"   // or a local dir
)
```

The model is a two-module chain: a mel front-end feeding an int8-weight
Whisper-Tiny encoder + completion head, running on ORT-CPU on Android,
shipped as `TheStageAI/smart-turn-v3` and downloaded/cached by the SDK
on first use. Knobs hot-apply at runtime via
`agent.update_turn_config(...)`.

**Why a confirm count.** A single model checkpoint can spike over
`turn_eot_threshold` on a brief mid-sentence pause. Requiring
`turn_eot_confirm_count` consecutive "done" verdicts (re-evaluated every
`turn_reeval_interval_ms`) debounces that, at the cost of a little latency.
The `turn_eot_high_confidence` fast-path (commit immediately on a very
confident single verdict) is **off by default** (`1.0`): the eval harness
showed it commits before enough trailing silence is buffered and clips the
last ASR word, even on 0.99-confident verdicts. Lower it (e.g. `0.97`) only
if you measure that it doesn't truncate finals on your audio.

### Streaming transcription (ASR)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `asr_streaming` | Boolean | `true` | Emit live partial captions (`user_request_partial`) while the user speaks. Purely cosmetic — the authoritative transcript is identical whether this is on or off. |
| `asr_partial_interval_ms` | Int | 600 | Minimum new audio between caption passes (bounds redundant decoding). Streaming only. |
| `speculative_whisper` | Boolean | `true` | Decode a speculative full-utterance pass at the first VAD pause so the final transcript is warm by end-of-turn (low-latency final). |

The ASR node runs **one unified path** with two decoupled consumers that
share a **single serial inference chain** (the model is never entered
concurrently):

- **Captions (cosmetic).** When `asr_streaming` is on, the node re-decodes
  the growing turn buffer every `asr_partial_interval_ms` (a VAD pause
  forces a pass early) and folds the result through **LocalAgreement-2**:
  only the prefix two consecutive hypotheses agree on is surfaced, so
  captions never flicker or retract. Committed text is published as
  `user_request_partial`. These partials never feed the LLM.
- **Authoritative.** At end-of-turn the node emits exactly one
  `user_request` (source `speech`). It reuses the most recent full-buffer
  decode (a caption or the speculative pass) when the buffer hasn't
  drifted; otherwise it decodes the whole buffer fresh. This is the
  **only** value that drives the LLM.

Because the authoritative decode is always a single full-utterance pass,
**both modes produce identical final text**; `asr_streaming` only decides
whether live captions are emitted along the way. When `asr_streaming` is
off, no caption passes run; the speculative pass (if `speculative_whisper`)
still warms the final at the VAD pause, so perceived STT latency stays near
**0 ms** in the steady state. The handoff is in-band: the turn node pushes
speculate / end-of-turn markers on the same wire that carries voiced
frames, so finalization stays in lock-step with the audio (no
cross-channel race).

### Interruption / AEC

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `interrupt_mode` | `InterruptMode` | `VAD` (≡ `speech_only`) | How (and whether) the user can barge in. Config-surface string values: `none` / `speech_only` / `wake_word`. |
| `allow_interruptions` | Boolean | `true` | Back-compat alias: `true` ⇔ `interrupt_mode != NONE` |
| `interrupt_min_speech_ms` | Int | 600 | Sustained speech needed to interrupt (Flutter slider goes down to 100 ms) |
| `interrupt_onset_ms` | Int | 0 | Sustained positive-VAD duration to fire a barge-in. When `> 0` it takes precedence over `interrupt_min_speech_ms`. |
| `interrupt_threshold` | Double | 0.9 | VAD prob threshold for barge-in, independent of `vad_threshold`. Kept strict so the agent doesn't trip on its own TTS / AEC residue. |
| `interrupt_min_playback_ms` | Int | 250 | Grace at TTS turn start during which barge-in is suppressed (lets AEC re-converge) |
| `interrupt_initial_lockout_ms` | Int | 1000 | One-time, longer barge-in lockout on the *first* TTS playback after start (covers AEC cold-start). Should exceed `aec_warmup_ms`. |
| `interrupt_thinking_lockout_ms` | Int | 600 | Barge-in lockout while `thinking` (mic live, AEC has no reference yet). 0 disables. |
| `aec_enabled` | Boolean | `true` | Platform acoustic echo cancellation, referencing the TTS playback output |
| `aec_warmup_ms` | Int | 250 | Silence pumped to the speaker on start so the AEC has reference samples |
| `aec_playback_gate_tail_ms` | Int | 80 | Sink-drain grace at end of every TTS turn |

```kotlin
enum class InterruptTrigger(val raw: String) {
    NONE("none"),               // Never interrupt; the mic is hard-muted during playback.
    SPEECH_ONLY("speech_only"), // Sustained user speech is enough to barge in.
    WAKE_WORD("wake_word")      // Wake word must fire during sustained speech to confirm.
}
```

`SPEECH_ONLY` is the default. On a device with unreliable echo
cancellation, use `NONE` so the audio engine drops mic samples while the
speaker is playing and VAD never sees the self-echo. Android echo
cancellation uses the platform `AcousticEchoCanceler`, which references
the TTS playback stream (route the player with `voice_processing = true`);
`aec_enabled` gates it.

### Wake-word standby

When `wake_word` is set, the orchestrator's resting state is
`sleeping`: VAD still runs, and the wake-word node classifies the same
voiced-audio fan-out wire that feeds STT. Only a wake-word detection
flips the agent to `listening`. After a turn finishes (or is
interrupted) the agent returns to `sleeping`.

When `wake_word` is `null`, `sleeping` is never entered and the resting
state between turns is `listening`.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `wake_word` | String? | `null` | HF id or local path of the wake-word bundle. Enables `sleeping` standby. |
| `ww_threshold_score` | Double | 0.5 | Probability the wake-word classifier must reach for a positive detection. Tune per model. |
| `ww_device` | String | `"npu"` | Wake-word compute device (see compute routing). |

## Events

The agent emits a modality-agnostic, lifecycle-oriented event vocabulary.
Each event is `{ kind, data }`:

| `kind` | `data` keys | When |
|--------|-------------|------|
| `state_changed` | `state` | State transition |
| `user_request_partial` | `text` | A stable partial caption was committed mid-turn (streaming ASR only). UI-only; does not drive the state machine. |
| `user_request` | `text`, `source` | A user request was finalized. `source` is `speech` (Whisper committed a turn) or `text` (a typed request via `send_request(...)`). Either way this is what drives the LLM. |
| `response_delta` | `delta` | An LLM token arrived |
| `response_done` | `text`, `reason`, `interrupted` | The response stream finished. `reason` is an end reason (`completed` / `interrupted` / `error` / `empty`); `interrupted` (Bool) is kept for back-compat. |
| `playback_started` | — | First TTS sample reached the speaker |
| `playback_ended` | `reason` | Speaker stopped. `reason` is `completed` (after the audio drained) or `interrupted` (barge-in). |
| `wake_word` | `prob` | The wake-word classifier fired. `prob` is the detection score. Only emitted when `wake_word` is configured. |
| `turn_start_accepted` | — | The turn-start policy accepted (the agent left `sleeping`). Only relevant when `wake_word` / turn-start gating is configured. |
| `voices` | `voices`, `current` | Available TTS voices discovered in the loaded bundle, plus the resolved active voice (`current`) — lets a host populate its voice picker from the bundle. |
| `metrics` | `loading_model`, ... | Heartbeat metrics |
| `error` | `message` | Recoverable error |

The vocabulary is deliberately invariant to *why* playback stopped:
playback lifecycle (`playback_started` / `playback_ended`) is distinct
from synthesis — `playback_ended(reason)` is what tells the UI whether
the agent finished naturally (`completed`) or was cut off
(`interrupted`), rather than overloading "TTS done".

For high-frequency or fan-out friendly signals, prefer the typed
channels (`llm_deltas`, `transcripts`, `vad_probabilities`) over parsing
`events`.

## Programmatic Controls

```kotlin
agent.interrupt()                     // cancel current response
agent.say("Hi there!")                // speak text, skip LLM (suspend)
agent.send_request("What time is it?") // inject a typed user turn -> LLM
agent.set_voice("dave")               // change TTS voice (suspend)
val history = agent.history()         // List<AgentMessage>
agent.clear_history()
agent.update_interrupt_config(        // hot-apply on a running agent
    min_speech_ms = 200,
    mode = InterruptTrigger.SPEECH_ONLY
)
agent.update_turn_config(             // "dnn" endpointer only; no-op otherwise
    eot_threshold = 0.6,
    pause_trigger_ms = 256
)
agent.stop()                          // unload models, release audio (suspend)
```

`update_interrupt_config(...)` and `update_turn_config(...)` are the knobs
that can be changed on a running graph today — they forward directly to the
live interruption / DNN-turn nodes. All other configuration is consumed
at `start()` and changing it requires a `stop()` + new
`TheStageVoiceAgent(config)`.

`send_request(text)` submits a typed turn that bypasses the mic and
ASR: it drives the exact same LLM → TTS path as a spoken turn (the
finalized `user_request` event carries `source = "text"`). It is a
no-op when the agent has no LLM responder (transcription-only). In
Flutter the same call is `agent.sendRequest(text)`.

## Custom Nodes

The agent graph is extensible: you can append your own nodes that run
on the agent's event loop, gated by lifecycle state, exchanging values
on named ports and reacting to the shared event bus. The SDK ships the
**primitives** (`TheStageAgentNode`, `AgentNodeContext`, `extraNodes`);
example nodes (live captions, event logs) belong in the host app.

**Flutter.** Implement `TheStageAgentNode` in Dart and pass instances
to `start(extraNodes: [...])`. Lifecycle hooks cross a native bridge by
string `id`:

```dart
class EventLogNode extends TheStageAgentNode {
  EventLogNode({this.onBusEvent});
  @override String get id => 'event_log';
  @override List<String> get runWhen => const [];   // empty = always open

  final void Function(Map<String, dynamic>)? onBusEvent;

  @override
  Future<void> onEvent(AgentNodeContext ctx, Map<String, dynamic> e) async {
    onBusEvent?.call(e); // e['kind'] = STATE | USER_REQUEST | BARGE_IN | …
  }
}

await agent.start(config: baseConfig, extraNodes: [EventLogNode(...)]);
```

`AgentNodeContext` carries the node's current `state`, `isGateOpen`
(whether the gate is open for the current state per `runWhen`), and the
port/bus helpers:

- `ctx.sendPort(name, value)` — push a value onto this node's output
  port. It surfaces on the multiplexed `agent.portEvents` stream (and
  `agent.subscribePort('$id.$name')`) as `{port: "$id.$name", value}`.
- `ctx.recvPort(name)` — `Stream<String>` of values sent to this node's
  named port.
- `ctx.publishEvent(event)` — inject a bus event. Supported today:
  `{'kind': 'USER_REQUEST', 'text': '...'}` (optional `'source'`:
  `speech` \| `text` \| `system`), which drives the LLM → TTS path as if
  the user spoke. This is the node-scoped form of `sendRequest`.

Gate heavy work (e.g. a local VLM) to **non-active** states by setting
`runWhen` to quiet states — treat `thinking` and `speaking` as active,
and prefer `idle` / `sleeping` / `listening` so you don't contend with
ASR / LLM / TTS for the NPU.

**Kotlin.** Subclass `TheStageAgentNode(id)`, override `start()` /
`stop()`, set `run_when`, and use the inherited `publish(event)`,
`subscribe()` (the bus as a `SharedFlow<AgentEvent>?` — null until the
node is bound) and `make_port(name)`.
Append via `config.copy(extra_nodes = listOf(node))`.

**Internal bus vs public events.** A custom node's `onEvent` sees the
**internal bus** vocabulary with UPPERCASE kinds — distinct from the
public snake_case `agent.events` in [Events](#events). Do not mix them:

| Bus `kind` | Meaning |
|------------|---------|
| `STATE` | Lifecycle transition (`state` field) — the primary gate for `runWhen` |
| `SPEECH_STARTED` / `SPEECH_ENDED` | VAD turn boundaries |
| `SPEECH_ONSET` | Sustained speech while interrupt policy evaluates |
| `BARGE_IN` | User interrupted the assistant |
| `WAKE_WORD_DETECTED` | Wake-word positive |
| `SPEAKER_VERIFIED` / `SPEAKER_REJECTED` | Speaker-ID gates |
| `TURN_START_ACCEPTED` | Left `sleeping` |
| `USER_REQUEST_PARTIAL` | Live caption (UI); never drives the LLM |
| `USER_REQUEST` | Final request → LLM |
| `RESPONSE_STARTED` / `RESPONSE_DONE` | Reply lifecycle |
| `SYNTHESIS_DONE` | Last TTS sample produced (not yet drained) |
| `PLAYBACK_STARTED` / `PLAYBACK_ENDED` | Speaker lifecycle |
| `ERROR` | Recoverable error string |

## Latency

The figures below use a remote OpenAI `gpt-4o-mini` LLM, so "first
audio" (time between end-of-user-speech and the first sample reaching
the speaker) is dominated by the network LLM time-to-first-token — the
on-device Snapdragon pipeline adds a comparable ~100–200 ms on top.

| Turn | LLM 1st tok | First audio | Full speak |
|------|------------:|------------:|-----------:|
| Short reply | ~490 ms | **~520 ms** | ~3.3 s |
| Long monologue | ~575 ms | **~600 ms** | **~53 s** |
| Mid-length | ~1230 ms | **~1500 ms** | ~5.8 s |

The on-device pipeline (VAD + speculative Whisper + LLM-delta-streamed
NeuTTS) adds only ~100–200 ms on top of the network round-trip. LLM
deltas are plumbed straight into the TTS streaming session, so sentence
segmentation and decoder context reuse happen inside TTS — the LLM node
never has to wait for sentence boundaries.

## Background Operation (Android)

To keep VAD / Whisper / TTS / wake word running while the app is
backgrounded, run the agent under a **foreground service** with the
microphone type. Declare the permissions and service in your app's
manifest:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />

<service
    android:name=".VoiceAgentService"
    android:foregroundServiceType="microphone"
    android:exported="false" />
```

Start the service (with an ongoing notification) before `agent.start()`
so the OS keeps the mic capture alive off-screen. The NPU keeps
executing the model graphs while backgrounded; the exact service
lifecycle wiring is app-side.

## Concurrency Note

`TheStageAI.infer` and `TheStageAI.infer_stream` run on their own
coroutine dispatchers, so VAD, Whisper, NeuTTS and the LLM stream run on
independent tasks inside the agent — none of them serialize on the main
thread. Each node in the graph is its own serial-queue-backed inference
loop; the orchestrator is just an event router and never sits on the hot
path. If you build your own orchestrator on top of these APIs, don't
wrap inference calls in `withContext(Dispatchers.Main) { ... }`; that
re-introduces the very serialization this design avoids.

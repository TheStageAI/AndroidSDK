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

// Event stream (state changes, transcripts, deltas, errors).
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
`llm` at an on-device LLM bundle from the [LLM](./llm.md) page (e.g.
`"TheStageAI/LFM2.5-1.2B"`). The agent runs it with thinking off, so
replies go straight to speech, and gives it the built-in
[tools](#tools) (weather, time, search, phone actions) unless you set
`llm_tools = "none"`.

## Quick Start (Flutter)

```dart
import 'dart:io';
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');

final agent = TSVoiceAgent();

agent.events.listen((event) {
  switch (event['kind']) {
    case 'state_changed': print('STATE: ${event['state']}');
    case 'user_request':  print('YOU: ${event['text']}');
    case 'response_delta': stdout.write(event['delta']);
    case 'response_done': print('\nASSISTANT DONE');
  }
});

// Typed broadcast streams (one EventChannel each).
agent.llm_deltas.listen((delta) { /* update assistant bubble */ });
agent.transcripts.listen((text) { /* show user turn */ });
agent.vad_probabilities.listen((p) { /* drive a level meter */ });
agent.tts_levels.listen((level) { /* animate an avatar */ });

final caps = await agent.start(config: {
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
await agent.update_interrupt_config(interrupt_min_speech_ms: 200);
await agent.stop();
```

`start()` returns the agent's [capabilities](#capabilities) and also
keeps them in `agent.capabilities`.

## Capabilities

What a started agent can actually do depends on the stack it built: a
config without `tts` is transcription-only, a config without an LLM
never answers. The agent reports this after `start()`:

| Key | Type | `true` when |
|-----|------|-------------|
| `listening` | bool | The mic and VAD are running |
| `transcribing` | bool | Speech recognition is running |
| `responding` | bool | A spoken turn reaches an LLM that answers |
| `speaking` | bool | TTS is running: replies and `say()` are heard |
| `reasons` | `Map<String, String>` | One entry per `false` capability, keyed by its name, e.g. `{'speaking': 'no tts configured (transcription-only)'}` |

`responding` is `false` without an LLM, for `llm_provider = "local"`
without an `llm` path, for an empty `llm_endpoint`, and with
`turn_end_mode = TurnEndMode.NONE` (Flutter `'turn_end_mode': 'none'`;
no turn ever ends, so speech never reaches the LLM; `send_request`
still does).

After `start()` with `auto_listen = false`, `listening` is `false`
(reason: the mic is not open yet) until
[`begin_listening()`](#deferred-mic-auto_listen); `transcribing` and
`responding` follow it. In Flutter, `begin_listening()` and
`set_voice()` refresh `agent.capabilities`.

Set `require_full_stack` to make `start()` fail unless the configured
stack — audio input + VAD, speech recognition, LLM and TTS — was
built. The error lists the reasons, and nothing keeps running. A
deferred mic (`auto_listen = false`) does not fail it.

**Kotlin:**

```kotlin
val agent = TheStageVoiceAgent(config.copy(require_full_stack = true))
agent.start()                       // throws IllegalStateException
val caps = agent.capabilities       // TheStageAgentCapabilities
if (!caps.speaking) println(caps.reasons["speaking"])
```

**Flutter:**

```dart
final caps = await agent.start(config: config);
if (caps['speaking'] != true) {
  print((caps['reasons'] as Map)['speaking']);
}

// Or fail fast:
await agent.start(config: config, require_full_stack: true);
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
await agent.begin_listening();
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

         a tool call inside a turn:
         thinking ─► tool_calling ─► thinking ─► speaking
         speaking ─► tool_calling ─► speaking   (a spoken filler first)
```

| State | Meaning |
|-------|---------|
| `idle` | Models not loaded |
| `loading` | Models being downloaded / loaded |
| `sleeping` | Wake-word standby. VAD/WW are live, ASR/LLM/TTS are gated off. Only entered when `wake_word` is configured. |
| `listening` | Mic open, VAD scanning for speech |
| `thinking` | Speech committed, LLM is generating |
| `tool_calling` | The model called a tool and the agent is running it. Barge-in works and cancels the tool. Left for `speaking` if the reply's audio already started, else `thinking`. |
| `speaking` | TTS streaming audio to the speaker |

State is derived inside the orchestrator from the event stream and is
the only place the state machine lives. It is broadcast as a
`state_changed` event and also exposed as `agent.state`
(`StateFlow<TheStageAgentState>` in Kotlin, `TSAgentState` in Flutter).

## Public Output Channels

In addition to the `events` stream, the agent exposes typed
fan-out ports as plain Kotlin `Flow`s. Each collector sees every value
— perfect for plugging UI widgets, log taps and speech-to-file
recorders side-by-side without intermediate bookkeeping.

| Property | Type | What it carries |
|----------|------|-----------------|
| `agent.llm_deltas` | `Flow<String>` | Each LLM token delta as it is generated, in order |
| `agent.transcripts` | `Flow<String>` | One value per user turn (the finalized Whisper transcript; empty on aborted turns) |
| `agent.vad_probabilities` | `Flow<Double>` | Per-frame Silero probability ([0, 1]); roughly one value every 32 ms |
| `agent.tts_levels` | `Flow<Double>` | Loudness of the assistant's speech as it plays ([0, 1]); about 30 values per second while speaking, then a single `0.0` when playback ends or is interrupted |
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

The same channels are exposed in Flutter as `agent.llm_deltas`
(`Stream<String>`), `agent.transcripts` (`Stream<String>`),
`agent.vad_probabilities` (`Stream<double>`) and `agent.tts_levels`
(`Stream<double>`), each backed by its own `EventChannel`.

### Speech level for an avatar

`tts_levels` is computed from the audio actually handed to the
speaker, so it follows what the user hears, not how fast the TTS
synthesises. Each ~33 ms window of playback is measured as RMS and
mapped from decibels onto [0, 1]: −55 dBFS and below is `0.0`,
−10 dBFS and above is `1.0`, linear in between (normal speech sits
around 0.6–0.9). Values are paced to playback, at most about 30 per
second, and the stream ends each reply with `0.0`, so a mouth closes
on its own after the last word or a barge-in. Nothing is emitted while
the agent is silent.

**Kotlin**

```kotlin
lifecycleScope.launch {
    agent.tts_levels.collect { level ->
        avatar.mouth_open = level.toFloat()   // 0 = closed
    }
}
```

**Flutter**

```dart
final mouth = ValueNotifier<double>(0);
final sub = agent.tts_levels.listen((level) => mouth.value = level);

// In build():
ValueListenableBuilder<double>(
  valueListenable: mouth,
  builder: (_, level, __) => Transform.scale(
    scaleY: 0.2 + 0.8 * level,
    child: const Icon(Icons.circle, size: 48),
  ),
);
// ...later
await sub.cancel();
```

## Configuration

### Models

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `vad` | String | required | HF id or local path of Silero VAD bundle |
| `stt` | String | required | HF id or local path of Whisper bundle |
| `tts` | String? | `null` | HF id or local path of NeuTTS bundle (required to speak) |
| `tts_voice` | String | `"paul"` | Voice id from the TTS bundle |
| `tts_voice_dir` | String? | `null` | A [voice pack](#voices) folder holding `voice.json`. Wins over `tts_voice` |
| `tts_language` | String? | `null` | TTS language override, e.g. `"french"`. `null` = the voice's own language |
| `wake_word` | String? | `null` | Optional wake-word bundle — HF id or local path. When set, the agent rests in `sleeping` until the wake word fires. A wake-word model recognises one specific phrase, so none ships with the SDK: bring your own. |
| `stt_language` | String | `"en"` | Whisper decode language (ISO-639-1, e.g. `"en"`, `"es"`) |
| `stt_revision` | String | `""` | STT commit; empty = the commit this SDK pins. Leave it empty |
| `tts_revision` | String | `""` | TTS commit; empty = the pinned commit. Leave it empty |
| `vad_revision` | String | `""` | VAD commit; empty = the pinned commit. Leave it empty |
| `ww_revision` | String | `""` | Wake-word commit; empty = the pinned commit |
| `speaker_id` | String? | `null` | Speaker-id bundle (`TheStageAI/redimnet2`) — HF id or local path. Loaded only when a `turn_start_mode` or `interrupt_mode` needs speaker verification |
| `speaker_id_revision` | String | `""` | Speaker-id commit; empty = the pinned commit |
| `speaker_similarity_threshold` | Double | 0.75 | Similarity to the enrolled embedding a speaker must reach to be verified |
| `enrolled_speaker_embedding` | `DoubleArray?` (Flutter `List<double>`) | `null` | The speaker to verify against; or call `enroll_speaker` on a running agent |
| `require_full_stack` | Boolean | `false` | Fail `start()` unless every [capability](#capabilities) is available |
| `component_offload` | Boolean | `false` | Kotlin only. Memory optimization: swap STT (whisper) and the TTS-LLM in/out of memory across listening/speaking so they never co-reside. Default off = always-loaded. |

### Compute device routing (Snapdragon NPU)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `vad_device` | String | `""` | Silero VAD bundle class |
| `stt_device` | String | `""` | Whisper bundle class |
| `stt_devices` | `Map<String,String>?` | `null` | Per-module override: `mel`, `encoder`, `decoder` |
| `tts_device` | String | `""` | NeuTTS bundle class |
| `tts_devices` | `Map<String,String>?` | `null` | Per-module override: `llm`, `neucodec` |
| `llm_device` | String | `""` | On-device LLM bundle class (`llm_provider = "local"`) |
| `ww_device` | String | `""` | Wake-word bundle class |
| `turn_detector_device` | String | `""` | smart-turn bundle class |
| `speaker_id_device` | String | `""` | Speaker-id bundle class |

Leave every `*_device` empty: each component then loads the best
bundle its model publishes for the phone, exactly like
`start_model(device = "")` (see
[Choosing the device](./model_management.md#choosing-the-device)).
`"npu"` or `"cpu"` is a constraint: `start()` fails if that model
publishes no such bundle — Silero VAD, for one, publishes only a CPU
bundle.

The Qualcomm Snapdragon NPU (Hexagon) runs the heavy models: Whisper's
encoder/decoder and the on-device LLM on TheStage's own NPU runtime,
the NeuTTS LLM through QNN (compiled context binaries). Both keep running when the app is in the background
(with a foreground service). Small stateful models (Silero VAD, the
smart-turn classifier) run on ORT-CPU regardless — they don't benefit
from the NPU. Some sub-modules are pinned per the bundle's
`metadata.json` (e.g. the Whisper mel front-end stays on CPU).

### LLM

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `llm_provider` | String | `"local"` (Flutter: `"openai_compatible"`) | `"local"` (on-device SDK model) or `"openai_compatible"` (remote SSE chat-completions) |
| `llm` | String? | `null` | Local: engines path of the on-device LLM |
| `llm_revision` | String | `""` | Local LLM commit; empty = the pinned commit. Leave it empty |
| `llm_model` | String | `"gpt-4o-mini"` | Remote model id |
| `llm_endpoint` | String | OpenAI chat-completions | Remote endpoint URL |
| `llm_api_key` | String | `""` | Remote API key |
| `llm_provider_override` | `LlmProvider?` | `null` | Kotlin only. Inject a custom / mock provider (overrides the above) |
| `system_prompt` | String | `DefaultTools.voice_system_prompt` | Prepended as a system message. The default is a short spoken assistant that knows when and how to use [tools](#tools). |
| `llm_tools` | String | `"voice"` | Built-in [tools](#tools) of the on-device LLM: `voice`, `web`, `phone` or `none` |
| `tools` | `List<Tool>?` | `null` | Kotlin only: your own tools for the on-device LLM; replaces the `llm_tools` preset |
| `max_tokens` | Int | 256 | Generation cap |
| `temperature` | Double | 0.7 | Sampling temperature |
| `chat_memory` | `ChatMemory` | `SlidingWindowMemory(max_turns = 10)` | Kotlin only. History strategy |

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
(`turn_end_mode = TurnEndMode.VAD`); the DNN endpointer ignores it.

### Turn detection (end-of-turn)

The endpointer is pluggable (`turn_end_mode`; Flutter strings in
brackets). `VAD` (`'vad'`, default) commits a turn after a
fixed silence gap (`silence_timeout_ms`). `DNN` (`'dnn'`) replaces that with the
pipecat **smart-turn-v3** model: at each pause it runs a learned
end-of-turn check on the trailing waveform, so the agent waits through
mid-sentence pauses but responds quickly once you're actually done.
`NONE` (`'none'`) never fires end-of-turn (continuous transcription).

VAD is the cheap gate (onset + pause detection); the DNN is the expensive
semantic check run **single-flight, off-thread, only at pauses**, with a hard
`turn_max_silence_ms` floor so it can never hang or classify an empty
window. The model sees the **continuous** waveform from onset (incl. pre-roll)
through the pause — never VAD-filtered audio.

### Using the turn detector on its own

The classifier is also a model you can start and call directly, if you
are building your own turn-taking rather than using the voice agent.
Start `TheStageAI/smart-turn-v3` like any other model and pass the
trailing waveform:

```json
{ "audio": [ ... 16 kHz mono floats in [-1, 1] ... ] }
```

It returns `[{"probability": 0.91}]` — the probability that the turn
is **complete**. Pass the continuous audio from speech onset through
the current pause; any length works, since the front-end keeps the
last 8 s and left-pads a shorter tail.

A second key, `input_features`, accepts a pre-computed 80 × 800 log-mel
if you already hold one. Pass **one or the other** — passing both is an
error rather than a precedence rule, because the two cannot be told
apart at runtime: 80 × 800 mel floats is exactly 4.0 s of 16 kHz PCM,
so a length heuristic would silently read audio as features and return
a confident wrong answer.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `turn_end_mode` | `TurnEndMode` | `VAD` | `VAD` (silence timeout), `DNN` (smart-turn model) or `NONE`; Flutter `'vad'` / `'dnn'` / `'none'` |
| `turn_detector` | String | `"TheStageAI/smart-turn-v3"` | smart-turn engines repo/path (used only for `DNN`) |
| `turn_detector_revision` | String | `""` | smart-turn commit; empty = the pinned commit |
| `turn_detector_device` | String | `""` | Bundle class for the classifier; empty = best available (it runs on the CPU) |
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
import ai.thestage.qlip.voice_agent.graph.TurnEndMode

val config = TheStageAgentConfig(
    vad = ..., stt = ..., tts = ..., llm_provider = "local", llm = ...,
    turn_end_mode = TurnEndMode.DNN,
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
confident single verdict) is **off by default** (`1.0`): it can commit
before enough trailing silence is buffered and clip the last ASR word, even
on 0.99-confident verdicts. Lower it (e.g. `0.97`) only if you measure that
it doesn't truncate finals on your audio.

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
| `interrupt_mode` | `InterruptMode` | `VAD` | How (and whether) the user can barge in — see below. Flutter: the mode's string, e.g. `'none'` or `'vad'` |
| `interrupt_min_speech_ms` | Int | 600 | Sustained speech needed to interrupt |
| `interrupt_onset_ms` | Int | 0 | Sustained positive-VAD duration to fire a barge-in. When `> 0` it takes precedence over `interrupt_min_speech_ms`. |
| `interrupt_threshold` | Double | 0.9 | VAD prob threshold for barge-in, independent of `vad_threshold`. Kept strict so the agent doesn't trip on its own TTS / AEC residue. |
| `interrupt_min_playback_ms` | Int | 250 | Grace at TTS turn start during which barge-in is suppressed (lets AEC re-converge) |
| `interrupt_initial_lockout_ms` | Int | 1000 | One-time, longer barge-in lockout on the *first* TTS playback after start (covers AEC cold-start). Should exceed `aec_warmup_ms`. |
| `interrupt_thinking_lockout_ms` | Int | 600 | Barge-in lockout while `thinking` (mic live, AEC has no reference yet). 0 disables. |
| `interrupt_post_tool_lockout_ms` | Int | 900 | Barge-in lockout after a tool returns (`tool_calling` → `thinking` / `speaking`). Speech heard meanwhile still counts toward the barge-in. |
| `aec_enabled` | Boolean | `true` | Platform acoustic echo cancellation, referencing the TTS playback output |
| `aec_warmup_ms` | Int | 250 | Silence pumped to the speaker on start so the AEC has reference samples |
| `aec_playback_gate_tail_ms` | Int | 80 | Sink-drain grace at end of every TTS turn |

The AEC fields are accepted from the Flutter config under the same
keys.

`InterruptMode` (`ai.thestage.qlip.voice_agent.graph`; Flutter string
in brackets):

| Mode | Barge-in when |
|------|---------------|
| `NONE` (`'none'`) | Never; the mic is hard-muted during playback |
| `VAD` (`'vad'`, default) | Sustained user speech |
| `VAD_WAKE_WORD` (`'vad_wake_word'`) | The wake word fires during sustained speech |
| `VAD_SPEAKER_ID` (`'vad_speaker_id'`) | The enrolled speaker is verified during sustained speech |
| `VAD_SPEAKER_ID_WAKE_WORD` (`'vad_speaker_id_wake_word'`) | Both of the above |

On a running agent, `update_interrupt_config(mode = …)` takes an
`InterruptTrigger` — `NONE`, `SPEECH_ONLY` or `WAKE_WORD` (Flutter
`interrupt_mode: 'none' | 'speech_only' | 'wake_word'`).

On a device with unreliable echo cancellation, use `NONE` so the
audio engine drops mic samples while the speaker is playing and VAD
never sees the self-echo. Android echo cancellation uses the platform
`AcousticEchoCanceler` on the mic capture
(`AudioInputConfig.voice_processing`), referencing the TTS playback;
`aec_enabled` turns it on.

### Volume

The agent plays in Android's voice-call audio session, which echo
cancellation needs, so the phone's volume keys set its loudness while
it runs (Android shows them as the in-call volume). The SDK widens
that range so the lowest steps are quiet. The media volume does not
affect the agent.

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
| `ww_threshold_score` (Flutter `ww_threshold`) | Double | 0.5 | Probability the wake-word classifier must reach for a positive detection. Tune per model. |
| `ww_device` | String | `""` | Wake-word bundle class; empty = best available (see compute routing). |
| `turn_start_mode` | `TurnStartMode` (Flutter string) | `VAD` (`'vad'`) | What leaves `sleeping`: `VAD_WAKE_WORD` (`'vad_wake_word'`) the wake word; `VAD_SPEAKER_ID_WAKE_WORD` (`'vad_speaker_id_wake_word'`) the wake word from the enrolled speaker. With `wake_word` set, `VAD` acts as `VAD_WAKE_WORD` |

## Tools

With the on-device LLM (`llm_provider = "local"`), the model can call
tools in the middle of a reply: it speaks a short filler ("Let me
check."), calls the tool, and answers from the result. The SDK runs
the tool; the UI sees it as the `tool_calling` state and a
`tool_started` / `tool_ended` event pair. Only the reply text is ever
spoken or sent on `llm_deltas`: the call markup, the arguments and
the tool's result never reach TTS.

Pick the tools with `llm_tools` (missing = `voice`):

| `llm_tools` | Tools |
|-------------|-------|
| `voice` (default), `all`, `true` | `get_weather`, `get_local_time`, `web_search`, `wikipedia_summary`, `calculate` and the `phone` tools |
| `web`, `live` | `get_weather`, `get_local_time`, `web_search` |
| `phone` | `open_url`, `dial_phone`, `open_maps`, `compose_sms`, `compose_email`, `copy_to_clipboard`, `get_battery` |
| `none`, `off`, `false` | No tools |

Tools need an LLM that can call them: the LFM2.5, LFM3 and Qwen3.5
models can. An OpenAI-compatible endpoint
(`llm_provider = "openai_compatible"`) gets no tools.

**Kotlin.** Pass your own tools in `tools` (they replace the preset;
add `DefaultTools.voice` to keep all the built-ins, or a smaller set
such as `DefaultTools.phone`). A tool's `execute`
receives the call and returns a short string the model reads. See
[LLM](./llm.md) for writing tools.

```kotlin
val order_status = Tool(
    name = "order_status",
    description = "Delivery status for an order number. " +
        "Use when the user asks where an order is.",
    parameters = mapOf(
        "type" to "object",
        "properties" to mapOf(
            "order_id" to mapOf("type" to "string"),
        ),
        "required" to listOf("order_id"),
    ),
    execute = { call ->
        orders.status_json(call.arguments["order_id"] as? String ?: "")
    },
)

val config = TheStageAgentConfig(
    vad = "TheStageAI/silero-vad",
    stt = "TheStageAI/thewhisper-large-v3-turbo",
    tts = "TheStageAI/neutts-multilingual",
    llm_provider = "local",
    llm = "TheStageAI/LFM2.5-1.2B",
    tools = listOf(order_status) + DefaultTools.phone,
    system_prompt = DefaultTools.voice_system_prompt +
        "\nYou help Acme customers.",
)

launch {
    agent.events.collect { e ->
        when (e.kind) {
            TheStageAgentEvent.Kind.TOOL_STARTED ->
                chip.show(e.data["name"] as String)
            TheStageAgentEvent.Kind.TOOL_ENDED -> chip.hide()
            else -> {}
        }
    }
}
```

**Flutter.** Choose a built-in preset; custom tools are Kotlin only.

```dart
await agent.start(config: {
  ...agentConfig,
  'llm_provider': 'local',
  'llm': 'TheStageAI/LFM2.5-1.2B',
  // voice (default) | web | phone | none
  'llm_tools': 'web',
});
agent.events.listen((e) {
  if (e['kind'] == 'tool_started') chip.show(e['name'] as String);
  if (e['kind'] == 'tool_ended') chip.hide();
});
```

**Spoken filler.** The model only says something before a tool call if
the system prompt asks it to. `DefaultTools.voice_system_prompt` does
(its "Tool pattern (always):" block). A system prompt of your own
without such a pattern gets the SDK's spoken-tool instruction appended
while tools are on; keep the line "Tool pattern (always):" in your
prompt to write the pattern yourself instead.

**Barge-in.** Speaking over the agent while a tool runs cancels the
tool and the reply (`response_done` with `interrupted: true`; the cut
tool gets no `tool_ended`). For `interrupt_post_tool_lockout_ms` after
a tool returns, barge-in waits so the answer can start.

> **Privacy.** The `web` tools send what the user asked about over the
> network: city names to Open-Meteo (weather, local time) and search
> queries to DuckDuckGo and Wikipedia. The `phone` tools open other
> apps (browser, dialer, maps, SMS and e-mail composers) with fields
> filled in; the user confirms the call or message there. The SDK
> never logs tool arguments or results, and `tool_started` /
> `tool_ended` carry them only to your app. Set `llm_tools` to `none`
> (or `phone`) to keep every request on the device.

## Events

The agent emits a modality-agnostic, lifecycle-oriented event vocabulary.
In Kotlin each event is a `TheStageAgentEvent(kind, data)`; in Dart it
is one flat map, `{'kind': …}` plus the `data` keys below (e.g.
`event['state']`):

| `kind` | `data` keys | When |
|--------|-------------|------|
| `state_changed` | `state` | State transition |
| `user_request_partial` | `text` | A stable partial caption was committed mid-turn (streaming ASR only). UI-only; does not drive the state machine. |
| `user_request` | `text`, `source` | A user request was finalized. `source` is `speech` (Whisper committed a turn) or `text` (a typed request via `send_request(...)`). Either way this is what drives the LLM. |
| `response_delta` | `delta` | An LLM token arrived |
| `response_done` | `text`, `reason`, `interrupted` | The response stream finished. `reason` is an end reason (`completed` / `interrupted` / `error` / `empty`); `interrupted` (Bool) is `true` when `reason` is `interrupted`. |
| `tool_started` | `name`, `arguments` | The model called a [tool](#tools). `arguments` is a JSON object string. |
| `tool_ended` | `name`, `content` | The tool returned `content` (what the model reads; never spoken). |
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
channels (`llm_deltas`, `transcripts`, `vad_probabilities`,
`tts_levels`) over parsing
`events`.

## Programmatic Controls

```kotlin
agent.interrupt()                     // cancel current response
agent.say("Hi there!")                // speak text, skip LLM (suspend)
agent.send_request("What time is it?") // inject a typed user turn -> LLM
agent.set_voice(voice_id = "dave")    // change TTS voice (suspend)
agent.set_system_prompt("Answer in French.")
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

**Flutter:**

```dart
await agent.interrupt();
await agent.say('Hi there!');
await agent.send_request('What time is it?');
await agent.set_voice(voice_id: 'dave');
await agent.set_system_prompt('Answer in French.');
await agent.clear_history();
await agent.update_interrupt_config(
  interrupt_min_speech_ms: 200,
  interrupt_mode: 'speech_only',
);
await agent.enroll_speaker(embedding: reference);  // null clears
await agent.stop();
```

`update_interrupt_config(...)`, `update_turn_config(...)` (Kotlin),
`set_voice(...)` and `set_system_prompt(...)` change a running agent.
`set_system_prompt` applies from the next reply and keeps the history.
All other configuration is consumed at `start()` and changing it
requires a `stop()` + new `TheStageVoiceAgent(config)`.

`send_request(text)` submits a typed turn that bypasses the mic and
ASR: it drives the exact same LLM → TTS path as a spoken turn (the
finalized `user_request` event carries `source = "text"`). It is a
no-op when the agent has no LLM responder (transcription-only). In
Flutter the same call is `agent.send_request(text)`.

## Voices

`set_voice` swaps the TTS voice on a running agent; it reloads the TTS
model, so call it between turns. `stop()` waits for an in-flight
`start()` or `set_voice()` to finish. Pass any subset of three fields —
fields you leave out keep their current value:

- **`voice_id`** picks a voice that ships in the TTS bundle (the
  `voices` event lists them).
- **`voice_dir`** points at a voice pack: **one folder holding a
  `voice.json`** (yours, or a downloaded one). It wins over
  `voice_id`. An empty `voice_dir` clears it and returns to
  `voice_id`.
- **`language`** switches the language while keeping the speaker. An
  empty `language` returns to the voice's own language.

```kotlin
agent.set_voice(voice_id = "dave")
agent.set_voice(voice_id = "dave", language = "french")
agent.set_voice(voice_dir = packDir.path)   // your own voice pack
agent.set_voice(voice_dir = "")             // back to the bundle voice
```

```dart
await agent.set_voice(voice_id: 'dave', language: 'french');
await agent.set_voice(voice_dir: packDir.path);
await agent.set_voice(voice_dir: '');
```

To start with a voice pack or a language, set `tts_voice_dir` /
`tts_language` in the config. `set_voice` throws (Kotlin) or completes
with an error (Flutter) for a relative `voice_dir` (it must be an
absolute path), a folder without `voice.json`, an unknown `voice_id`
or language, or a failed reload; the current voice stays. If the
previous voice cannot be restored either, the agent emits an `error`
event and stops speaking (`speaking` capability `false`). Voice packs
work on the multilingual NeuTTS bundles; with the English-only nano
bundle a `voice_dir` fails the same way.

A NeuTTS multilingual voice pack is a folder made offline from a
3–10 s reference clip (see [TTS](./tts.md#voicejson-shape)); its
`voice.json` holds `name`, `language`, `ref_text` and `ref_codes` (NeuCodec codes of the clip),
plus optional sampling defaults (`temperature`, `top_k`,
`min_new_tokens`, `use_lang_token`). Copy the folder to a real path on
the device (out of app assets, or download it) and pass that path.

## Custom Nodes

The agent graph is extensible: you can append your own nodes that run
on the agent's event loop, gated by lifecycle state, exchanging values
on named ports and reacting to the shared event bus. The SDK ships the
**primitives** (`TSAgentNode`, `AgentNodeContext`, `extra_nodes`);
example nodes (live captions, event logs) belong in the host app.

**Flutter.** Implement `TSAgentNode` in Dart and pass instances
to `start(extra_nodes: [...])`. Lifecycle hooks cross a native bridge by
string `id`:

```dart
class EventLogNode extends TSAgentNode {
  EventLogNode({this.onBusEvent});
  @override String get id => 'event_log';
  @override List<String> get runWhen => const [];   // empty = always open

  final void Function(Map<String, dynamic>)? onBusEvent;

  @override
  Future<void> onEvent(AgentNodeContext ctx, Map<String, dynamic> e) async {
    onBusEvent?.call(e); // e['kind'] = STATE | USER_REQUEST | BARGE_IN | …
  }
}

await agent.start(config: baseConfig, extra_nodes: [EventLogNode(...)]);
```

`AgentNodeContext` carries the node's current `state`, `isGateOpen`
(whether the gate is open for the current state per `runWhen`), and the
port/bus helpers:

- `ctx.sendPort(name, value)` — push a value onto this node's output
  port. It surfaces on the multiplexed `agent.port_events` stream (and
  `agent.subscribe_port('$id.$name')`) as `{port: "$id.$name", value}`.
- `ctx.recvPort(name)` — `Stream<String>` of values sent to this node's
  named port.
- `ctx.publishEvent(event)` — inject a bus event. Supported today:
  `{'kind': 'USER_REQUEST', 'text': '...'}` (optional `'source'`:
  `speech` \| `text` \| `system`), which drives the LLM → TTS path as if
  the user spoke. This is the node-scoped form of `send_request`.

Gate heavy work (e.g. a local VLM) to **non-active** states by setting
`runWhen` to quiet states — treat `thinking`, `tool_calling` and
`speaking` as active,
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

## Upgrading from 1.0.x

- Every `*_device` field defaults to `""`, the best available bundle
  (they were `"npu"` / `"cpu"`). A 1.0.x config that forces `"npu"`
  fails for components that publish only a CPU bundle, such as VAD —
  drop those overrides.
- `set_voice` reports failures (see [Voices](#voices)); in 1.0.x
  `setVoice` errors were swallowed.
- The Dart names `TheStageVoiceAgentFlutter`, `TheStageAgentNode`,
  `TheStageAgentState`, `TheStageAudioPlayer` and camelCase members
  such as `llmDeltas` or `setVoice` still compile as deprecated
  aliases of `TSVoiceAgent`, `TSAgentNode`, `TSAgentState`,
  `TSAudioPlayer` and the snake_case names on this page.
- The Flutter config keys `turn_detection_mode` and
  `allow_interruptions: false` are still read, as `turn_end_mode` and
  `interrupt_mode: 'none'`. In Kotlin, `turn_detection_mode`,
  `interrupt_trigger` and `allow_interruptions` are read-only
  properties derived from `turn_end_mode` and `interrupt_mode`.

# ASR (Speech-to-Text)

On-device speech recognition. Audio goes in as **16 kHz mono float**
samples and comes back as an `ASRResult`: the text, every word with its
start and end time, and the language. Nothing you record leaves the
device.

Use it in two ways: hand over a clip and get a transcript back, or open
a live session and get captions while the user is still talking.

- **One call for any length**: `ASREngine.infer` takes a two-second
  command or a forty-minute recording; windowing and stitching are
  automatic.
- **Live captions** come as two kinds of text at once: *committed*
  words that will not change, and a *hypothesis* that fills in ahead of
  them.
- **The SDK can own the microphone**: `TSASREngine` (Flutter) /
  `ASREngine(config)` (Kotlin) captures, detects speech and decides
  when an utterance ended. You only read text.
- **Or you keep your audio pipeline**: push 16 kHz frames into an
  `ASRStream` from any source.
- **Word timestamps** for seeking and highlighting (measured on
  Whisper, estimated on Qwen3-ASR).
- **Language detection**: `language: 'auto'`.

## Supported models

| Model | HF repo | Device | Window |
|---|---|---|---|
| TheWhisper Large V3 Turbo | `TheStageAI/thewhisper-large-v3-turbo` | NPU | 10 s |
| Qwen3-ASR 0.6B | `TheStageAI/Qwen3-ASR-0.6B` | NPU | 30 s |

| Feature | TheWhisper turbo | Qwen3-ASR 0.6B |
|---|---|---|
| Batch `infer` | yes | yes |
| Live captions (`ASRStream`, `TSASREngine`) | yes, sentence-level commits (`THESTAGE_V5`) | yes, agreed-prefix commits (`NAIVE`) |
| Word timestamps | yes, measured from the decoder's cross attention | yes, estimated (spread evenly over the window) |
| Language | ISO code, or `auto` | 30 ISO codes, or `auto` (the default) |
| Long audio | 10 s windows, stitched | 30 s windows, stitched |

Model-specific details (bundle, placement, load progress) are on
[whisper.md](./whisper.md) and [qwen3_asr.md](./qwen3_asr.md). Speech detection uses Silero VAD
(`TheStageAI/silero-vad`, [vad.md](./vad.md)).

## Quick start

Three ways to run ASR. They differ in **who owns the audio**:

| You want | Who owns audio | Flutter | Kotlin |
|---|---|---|---|
| A transcript of a clip | Nobody: you hand over samples | `ASREngine(stt:).infer` | `ASREngine.infer` |
| Live captions, shortest path | The SDK: mic, VAD and turns | `TSASREngine` | `ASREngine(config)` |
| Live captions from your own audio | You push PCM frames | `ASRStream.open` | `ASREngine.open_stream` |

### Transcribe a clip

**Flutter**

```dart
import 'dart:typed_data';
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');
await TheStageFlutterSDK.start_model(
  model_name: 'stt',
  engines_path: 'TheStageAI/thewhisper-large-v3-turbo',
);

// pcm16k: Float32List, 16 kHz mono, samples in [-1, 1]
final result = await ASREngine(stt: 'stt').infer(
  pcm16k,
  config: const ASRGenerationConfig(language: 'en'),
);
print(result.text);
```

**Kotlin**

```kotlin
import ai.thestage.qlip.TheStageAI
import ai.thestage.qlip.models.asr.ASRGenerationConfig

// Inside a coroutine.
TheStageAI.registerContext(context)
TheStageAI.initialize(api_token = "your-api-token")
TheStageAI.start_model(
    model_name = "stt",
    engines_path = "TheStageAI/thewhisper-large-v3-turbo",
)

val stt = TheStageAI.asr_engine(stt = "stt")
val result = stt.infer(pcm16k, ASRGenerationConfig(language = "en"))
println(result.text)
```

### Live captions: the SDK owns the microphone

The engine loads the models itself, captures the microphone, detects
speech and ends turns. The app needs the `RECORD_AUDIO` permission
granted before `start`.

**Flutter**

```dart
final asr = TSASREngine();

// Subscribe before start: nothing emitted earlier is replayed.
asr.turns.listen((turn) {
  committed.value = turn.committed;
  hypothesis.value = turn.end_of_turn ? '' : turn.hypothesis;
});
asr.transcripts.listen((text) => history.add(text));

await asr.start(config: {
  'vad': 'TheStageAI/silero-vad',
  'stt': 'TheStageAI/thewhisper-large-v3-turbo',
  'language': 'en',
});
// ... later
await asr.stop();
```

**Kotlin**

```kotlin
import ai.thestage.qlip.voice_agent.TheStageAgentConfig

val engine = TheStageAI.asr_engine(
    TheStageAgentConfig(
        vad = "TheStageAI/silero-vad",
        stt = "TheStageAI/thewhisper-large-v3-turbo",
        stt_language = "en",
    )
)
val captions = scope.launch {
    engine.turns.collect { turn ->
        committedLabel.text = turn.committed
        hypothesisLabel.text = if (turn.end_of_turn) "" else turn.hypothesis
    }
}
engine.start()
// ... later
engine.stop()
captions.join()
```

### Live captions: you own the audio

For audio that does not come from this device's microphone (a call,
a file, a network stream), or an app that already has an audio
pipeline. Start the models, open a stream, push frames.

**Flutter**

```dart
await TheStageFlutterSDK.start_model(
  model_name: 'vad', engines_path: 'TheStageAI/silero-vad');
await TheStageFlutterSDK.start_model(
  model_name: 'stt', engines_path: 'TheStageAI/thewhisper-large-v3-turbo');

final stream = await ASRStream.open(
  model_name: 'stt',
  vad_model_name: 'vad',
  generation: const ASRGenerationConfig(language: 'en'),
);
final captions = stream.events.listen((e) {
  if (!e.is_turn) return;
  committed.value = e.payload['committed'] as String;
  hypothesis.value = e.payload['end_of_turn'] == true
      ? '' : e.payload['hypothesis'] as String;
});

// Any 16 kHz mono Float32List frames, any size.
await for (final Float32List frame in remoteAudio16k) {
  await stream.send(frame);
}
final result = await stream.close();   // the transcript to store
await captions.cancel();
```

**Kotlin**

```kotlin
TheStageAI.start_model(
    model_name = "stt",
    engines_path = "TheStageAI/thewhisper-large-v3-turbo",
)
val stream = TheStageAI.asr_engine(stt = "stt")
    .open_stream(ASRGenerationConfig(language = "en"))

val captions = scope.launch {
    stream.turns.collect { turn -> render(turn.committed, turn.hypothesis) }
}
for (frame in remoteAudio16k) stream.send(frame)   // FloatArray
val result = stream.close()
captions.join()
```

## Transcribe audio

`infer` takes 16 kHz mono float samples of any length and returns one
`ASRResult`. Long audio is cut into 10 s windows; `overlap` reuses part
of each window in the next so a word on a cut is decoded by both and
kept once.

When the engine has a VAD (`ASREngine(stt: 'stt', vad: 'vad')`), each
window cut moves into a confirmed pause where one exists and windows
without speech are skipped. Windows stay contiguous audio, so
punctuation and word clocks are the same.

```dart
final stt = ASREngine(stt: 'stt', vad: 'vad');
final result = await stt.infer(
  pcm16k,
  config: const ASRGenerationConfig(
    language: 'en',
    timestamps: ASRTimestampMode.WORD,
    overlap: 0.2,
  ),
);
for (final w in result.words ?? const <ASRWord>[]) {
  print('${w.t0}s–${w.t1}s  ${w.text}');
}
```

Kotlin also reports progress: `ASREngine.infer_stream(audio, config)`
is a `Flow<ASRResult>` whose elements are the transcript so far (only
words no later window can change), and whose last element is the
result of `infer`.

**Audio contract.** `infer` and `send` do not convert audio.

| | |
|---|---|
| Sample rate | **16 000 Hz**. Other rates decode as time-warped speech and return nonsense or nothing. |
| Channels | Mono. Downmix stereo by averaging the channels. |
| Format | Float in `[-1, 1]`: Kotlin `FloatArray`, Flutter `Float32List` (not `Float64List`). From Int16: `sample / 32768`. |
| Loudness | Natural levels. Do not peak-normalise. |

**Per-call options**: `ASRGenerationConfig`.

| Field | Default | Meaning |
|---|---|---|
| `language` | `'en'` | ISO code, or `'auto'` to detect it. A wrong hint is worse than none: Whisper told `'en'` writes foreign speech as English. |
| `timestamps` | `WORD` | `NONE` is fastest; `SEGMENT` gives phrase ranges; `WORD` gives every word with `t0` / `t1`. |
| `overlap` | `0.2` | Share of a window reused by the next one, `0` to `< 1`. `0` decodes every sample once and can lose a word that straddles a cut. |
| `max_new_tokens` | unset | Cap on decode per window. Unset follows the audio length. |
| `return_tokens` | `false` | Include token IDs in the result. |
| `text_context` | `NONE` | `SUBMITTED` puts `context_text` into the decode prompt. |
| `context_text` | `''` | Text already final before this audio (with `text_context: SUBMITTED`). |
| `language_detection` | `false` | Omit the language hint and report the language the model predicts. |

## Live captions

Live recognition gives text while the user is still speaking, as two
kinds of text at once:

- **committed**: locked in, never rewritten. Render it solid.
- **hypothesis**: the current best guess at what is still being said.
  It will be rewritten. Render it lighter, after the committed text.

Every update is an `ASRTurn` (`TSASRTurn` from `TSASREngine`) with
`transcript`, `committed`, `hypothesis` and `end_of_turn`. When
`end_of_turn` is true the turn is finished: move `committed` into the
history and clear the live line.

```dart
asr.turns.listen((turn) {
  // Two widgets: solid text, then a dimmed guess.
  committed.value = turn.committed;
  hypothesis.value = turn.end_of_turn ? '' : turn.hypothesis;

  // One widget, if you must.
  caption.value = turn.display;

  // Wrong: appending display doubles words when the guess firms up.
  // transcript += turn.display;
});
```

Kotlin's `ASRStreamingBuffer` keeps the same pair for a view:
`apply(turn)` on each update, then bind `committed`, `hypothesis` or
`display`.

### The two modes

|  | SDK owns the mic | You push audio |
|---|---|---|
| Flutter | `TSASREngine` | `ASRStream.open(model_name:, vad_model_name:)` |
| Kotlin | `ASREngine(config)` / `TheStageAI.asr_engine(config)` | `ASREngine(stt, vad).open_stream(...)` |
| Models | Loaded by the engine from repo ids, released on `stop` | Started by you with `start_model` |
| Start / stop | `start` / `stop` | `open` / `close` (or `cancel`) |
| Turns | VAD + turn policy built in | `flush()` at a pause you detected; the commit policy ends turns on silence |

### SDK owns the microphone

Outputs of `TSASREngine` and of `ASREngine(config)`:

| Flutter stream | Kotlin flow | What arrives |
|---|---|---|
| `turns` | `turns` | Every turn update, partial and final. |
| `transcripts` | `transcripts` | One final string per completed utterance. |
| `partial_transcripts` | `partial_transcripts` | The running caption of the turn in progress. Latest value wins. |
| `vad_probabilities` | `vad_probabilities` | Per-frame speech probability in `[0, 1]`, for a level meter. |
| `events` | `events` | `{kind, data}`: `state_changed` `{state}`, `user_request` `{text, source}`, `user_request_partial` `{text}`, `error` `{message, code, node_id, recoverable}`. |
| — | `speaker_events` | Speaker updates; see [Speakers](#speakers). |

`TSASREngine.start(config:)` keys. Every key is optional; an absent key
keeps the tuned policy.

| Key | Default | Meaning |
|---|---|---|
| `vad` | `TheStageAI/silero-vad` | VAD repo id or local path. |
| `stt` | `TheStageAI/thewhisper-large-v3-turbo` | ASR repo id or local path. |
| `vad_device`, `stt_device` | best for the device | `npu` / `cpu`. |
| `stt_revision` | the pinned revision | A revision to load instead. |
| `language` | `en` | ISO code, or `auto`. |
| `turn_silence_timeout_ms` | the commit policy's `endpoint_silence_s` (1.5 s for Whisper) | Hush that ends a turn. |
| `turn_asr_silence_hangover_ms` | the commit policy's `silence_hang_s` (96 ms for Whisper) | Trailing hush still sent to the decoder, so the last word is not clipped. |
| `speakers` | off | `true`, or a map; see [Speakers](#speakers). |

Setting either turn key replaces the policy's turn timing: the key you
leave out then takes its `TurnConfig` default (608 ms, 300 ms).

`start` fails with `PlatformException` code
`THESTAGE_ASR_ENGINE_ERROR` when a model cannot load or the microphone
cannot open. Download progress arrives on
`TheStageFlutterSDK.on_progress`. Changing any key means `stop()` then
`start()`.

On Kotlin the same settings are `TheStageAgentConfig` fields:

| Field | Controls |
|---|---|
| `vad`, `stt`, `vad_device`, `stt_device`, `stt_revision` | The models. |
| `stt_language` | Language of the live session when `asr_generation` is unset. |
| `asr_generation` | The session's `ASRGenerationConfig`. |
| `turn_config` | When an utterance is over: `silence_timeout_ms` (608), `asr_silence_hangover_ms` (300 when unset), `max_accumulation_ms` (30 000). Unset: the commit policy's `endpoint_silence_s` and `silence_hang_s`. |
| `vad_config` | Capture sensitivity: `VADConfig` `threshold` (0.7), `neg_threshold` (0.15), `pre_roll_s` (0.30), `onset_window_s` (0.256). Unset: the loaded Silero VAD's tuning. |
| `speaker_setup`, `speakers` | Who said what; see [Speakers](#speakers). |
| `asr_streaming_config` | Commit policy; see [Configuration](#configuration). |
| `audio_node_factory` | Replace the microphone with your own audio node. |
| `on_load_progress` | Load progress of the models the engine starts. |

"It cuts me off mid-sentence" is `turn_config.silence_timeout_ms`. "It
starts on a door click" is `vad_config.threshold`. They are separate on
purpose.

### You push the audio

`ASRStream` calls (Flutter and Kotlin):

| Call | Use it to |
|---|---|
| `send(pcm)` | Push 16 kHz mono frames, any size. |
| `flush()` | End the current turn at a pause you detected; the stream stays open. |
| `close()` | End the session and get the final `ASRResult`. |
| `cancel()` | Abandon the session without a result. |

`close()` returns the transcript to store. The live text rendered from
turns may differ: it was produced before the model heard the end of the
sentence.

Flutter `ASRStream.events` carries `ASRStreamEvent`s; `kind` and
`payload`:

| `kind` | Payload |
|---|---|
| `begin` | The session opened. |
| `turn` | `transcript`, `committed`, `hypothesis`, `end_of_turn` (`speaker_id` when labelled). |
| `partial` | `text`: the committed text so far. |
| `termination` | `audio_seconds`; the session closed. |
| `cancelled` | The session was cancelled. |

A session that cannot open (model not started, unsupported option)
delivers a `PlatformException` with code `THESTAGE_STREAM_ERROR` on
`events`. Subscribe to `events` before the first `send`.

On Kotlin, `ASRStream` exposes `turns`, `partials`, `hypothesis` (the
live words) and `events` (`BEGIN`, `TURN`, `TERMINATION`) as flows.
Each flow is single-consumer and keeps only the newest value, so a slow
collector sees the latest snapshot rather than a backlog; all of them
complete at `close` or `cancel`.

## Result object

`ASRResult` is what `infer` and `close()` return.

| Kotlin / Dart field | Flutter JSON key | Meaning |
|---|---|---|
| `text` | `text` (also `transcription`) | The transcript. |
| `words` | `words` | `ASRWord` list: `text`, `t0`, `t1` in seconds, `speaker_id` when labelled. Present with `WORD` / `SEGMENT` timestamps. |
| `timestamp_mode` | `timestamp_mode` | `NONE`, `SEGMENT` or `WORD`. |
| `language` | `language` | The language decoded; the detected code with `auto`. |
| `generated_tokens` | `generated_tokens` (also `token_count`) | Tokens decoded, all windows. |
| `decode_seconds` | `decode_seconds` | Decoder wall time. |
| `tokens` | `tokens` | Token IDs, only with `return_tokens`. |
| `metrics` | `metrics` | `preprocess_seconds`, `encode_seconds`, `decode_seconds`, `total_seconds`, `audio_seconds`, `rtf` (audio seconds per wall second), `chunk_count`, `tokens_per_second`, `generated_tokens`. |

The raw rows of `TheStageFlutterSDK.infer` on an ASR model carry the
same keys; `ASRResult.from_json` parses them.

## Word timestamps

With `timestamps: WORD` (the default) each word has `t0` and `t1` in
seconds from the start of the audio. Whisper's times are measured: the
decoder's alignment heads' cross attention is aligned to the audio
frames, per window, then mapped onto the whole clip. Qwen3-ASR's times
are estimated: each window's words are spread evenly over it
(`ASRCapabilities.measured_word_times` is `false`). Build rows from
`result.words`, not by splitting `result.text`.

```dart
void seek(ASRWord word) =>
    player.seek(Duration(milliseconds: (word.t0 * 1000).round()));
```

On Whisper, live captions use the same measured times to commit whole
sentences at a time, which is why committed text arrives punctuated and
does not flicker.

## Language detection

`language: 'auto'` detects the language; `result.language` is its ISO
code. Whisper decodes the whole clip in the detected language: on long
audio the first windows with speech (up to three) vote, and the
majority wins. Qwen3-ASR names the language in the same decode as the
text, per window, and `result.language` is the last window's.

A correct hint is faster and more accurate than detection. Detect on
the first utterance, then pin the code:

```dart
final stt = ASREngine(stt: 'stt');
var result = await stt.infer(
  firstUtterance, config: const ASRGenerationConfig(language: 'auto'));
final detected = result.language ?? 'en';

result = await stt.infer(
  nextUtterance, config: ASRGenerationConfig(language: detected));
```

## Speakers

Speakers label every word and turn with who said it. Turn them on in
the engine's config; the models load with the others.

Flutter (`TSASREngine.start`):

```dart
await asr.start(config: {
  'stt': 'TheStageAI/thewhisper-large-v3-turbo',
  'speakers': true,
});
asr.turns.listen((t) => render(t.speaker_id, t.display));
```

`speakers` is `true` for the defaults, or a map with any of these keys:

| Key | Default | Meaning |
|---|---|---|
| `diarizer` | `TheStageAI/Nemotron-3-Diarization` | Diarizer repo id or local path. |
| `speaker_model` | `TheStageAI/speaker-id-v2` | Speaker-embedding model, loaded when `final_pass` or `voices_path` needs it. |
| `diarizer_revision`, `speaker_model_revision` | the pinned revision | A revision to load instead. |
| `final_pass` | `true` | At `stop()` the whole recording is diarized again and the words relabelled. |
| `voices_path` | none | A saved-voices file; matching speakers take its names. Only voices saved with the same `speaker_model` are matched; voices saved with another speaker model go unnamed, and saving a voice with the new model starts the file over in its space (the people and names stay, their old samples go). |

Kotlin: `TheStageAgentConfig.speaker_setup` takes the same settings as
a `SpeakerSetup` (`voices: SpeakerVoices?`, `final_pass`, `diarizer`,
`speaker_model`, `diarizer_revision`, `speaker_model_revision`).
`SpeakerSetup.conversation()` is the default. For models you have
already loaded, pass `speakers = ASRSpeakerConfig.conversation(
diarization, identification, enrolled)` instead, on
`TheStageAgentConfig` or on a push engine
(`ASREngine(pipeline, vad, speakers = ...)`,
`ASREngine(stt, vad, speakers)`).

With speakers, `ASREngine.infer` diarizes the whole clip and decodes
each speaker turn on its own audio; a live session decodes each
diarized speaker turn as it arrives, and `stop()` / `close()` returns
the final transcript with speakers.

| Where | Field |
|---|---|
| `ASRWord` | `speaker_id` |
| `ASRTurn` / `TSASRTurn` | `speaker_id` |
| `ASRResult` (Kotlin) | `speaker_turns`, `speaker_segments`, `speakers` |
| `ASREngine.speaker_events` / `ASRStream.speaker_events` (Kotlin flows) | Speaker-window updates for a model without measured word times: `turns_updated`, `speakers_updated`, `speakers_merged`, `reset`, `completed`, `failed`, `cancelled`, each with `session_id` and `sequence`. Whisper sessions label `turns` instead. |

Without speakers these fields are absent and `speaker_events` is empty.
Who-spoke-when on its own is [diarization.md](./diarization.md); voice
identity is [speaker_embedding.md](./speaker_embedding.md).

## Configuration

**Commit policy**: `ASRStreamingConfig`, for `ASRStream.open`
(`streaming:`) and Kotlin `open_stream` / `asr_streaming_config`.
Leaving it empty (`{}` on the wire) runs the policy tuned for the
loaded model; most apps never set it. Every field is an override.

| Algorithm | Behaviour |
|---|---|
| `THESTAGE_V5` | Whisper's default. Needs measured word times. Commits a sentence at a time, so punctuation and casing are right and text does not flicker. |
| `NAIVE` | Qwen3-ASR's default; runs on any model. Commits the longest prefix that repeated decodes agree on; more rewriting on screen. A turn ends after 3.5 s of silence. |
| `THESTAGE_V6` | Opt-in sentence-cut preview policy. |
| `THESTAGE_V5_5` | The V5 ladder with a faster first pass and fewer confirmations. |

| Field | Whisper default | Raise it / lower it when |
|---|---|---|
| `n_confirmations` | 2 | Raise for fewer rewrites, at the cost of text appearing later. |
| `commit_lag_s` | 1.0 s | How far behind live audio a word must be before it locks. Raise if endings get corrected; lower for snappier captions. |
| `endpoint_silence_s` | 1.5 s | How much hush ends a turn. |
| `max_repeats` | 3 | Raise if genuine repetition ("no no no") is removed; lower if a stuck decoder reaches the transcript. |
| `speech_onset_s` | 0.2 s | Raise if noise starts turns. |
| `format_turns` | `true` | `false` for raw words without sentence casing and punctuation. |

An algorithm the model cannot run (`THESTAGE_V5` without measured word
times) fails at open with the missing capability named; it is never
silently replaced.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Empty or nonsense transcript | Audio is not 16 kHz mono float. | Check the rate first; convert Int16 with `/ 32768`. |
| Words drop mid-file | `overlap: 0` and a word straddled a cut. | Leave `overlap` at `0.2`. |
| Foreign speech comes out as English | Wrong `language` hint. | `language: 'auto'`, then pin the detected code. |
| "Thank you." on silence | The decoder ran on hush. | Pass a VAD (`ASREngine(stt:, vad:)`) or use `TSASREngine`. |
| Captions are empty | Subscribed after `start` / the first `send`. | Subscribe first. |
| Text jumps around | Rendering `display` as if it were final. | `committed` solid, `hypothesis` dimmed. |
| `THESTAGE_ASR_ENGINE_ERROR` on `start` | A model failed to load, or no microphone permission. | `initialize` first; request `RECORD_AUDIO`. |
| `THESTAGE_STREAM_ERROR` on `events` | `model_name` / `vad_model_name` not started. | `start_model` both before `ASRStream.open`. |
| Flutter type error on `audio` | `Float64List` on the platform channel. | `Float32List`. |

## Load progress and cleanup

```dart
TheStageFlutterSDK.on_progress.listen((event) {
  print('[${event['model_name']}] ${event['phase']}');
});
await TheStageFlutterSDK.start_model(
  model_name: 'stt',
  engines_path: 'TheStageAI/thewhisper-large-v3-turbo',
);
// ...
await TheStageFlutterSDK.stop_model(model_name: 'stt');
```

`TSASREngine` releases the models it loaded on `stop()`. Beside a
voice agent on the same Whisper (or turn detector) it uses the
agent's loaded `stt` instead of loading a second copy; each side's
stop releases only its own hold, and the model unloads with the
last one. Its VAD is always a copy of its own. The full
progress contract is in [Load Progress](./README.md#load-progress).

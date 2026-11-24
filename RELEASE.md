# TheStage Android SDK 1.2.0

Pin this tag; the examples and the Flutter dependency use
`ref: v1.2.0`.

## What's new since 1.1.1

### New models

- **Qwen3-ASR-0.6B** (`TheStageAI/Qwen3-ASR-0.6B`, model type
  `qwen3-asr`): speech-to-text in 30 languages with language
  detection, through the same ASR API as Whisper. Word times are
  estimated (spread evenly over each window), so live captions use
  the `NAIVE` commit policy. NPU only: there is no CPU build. See
  [docs/qwen3_asr.md](./docs/qwen3_asr.md).
- **Phonon and Pocket TTS** (model types `phonon`, `pocket-tts`):
  small, fast TTS. Phonon 31M and Pocket TTS 18M in English; Pocket
  TTS 100M in French, German, Italian, Spanish, Portuguese, Dutch,
  Japanese, Chinese, Korean, Hindi, Polish, Turkish, Greek and
  Russian. Batch, streaming and voice folders. See
  [docs/phonon.md](./docs/phonon.md).
- **EmbeddingGemma 2** (`TheStageAI/embeddinggemma-2`, model type
  `embedding-gemma`): one embedding space for text, images, audio
  and video, with task prompts and Matryoshka dimensions.
  EmbeddingGemma (`TheStageAI/embeddinggemma-300m`) stays available
  for text. See [docs/embedding_gemma.md](./docs/embedding_gemma.md).
- **GLiNEREL-72m** (`TheStageAI/GLiNEREL-72m`, model type
  `glinerel`): entities, personal data and relations from free-text
  labels, with redaction. See [docs/glinerel.md](./docs/glinerel.md).
- **Speaker ID on the NPU** (`TheStageAI/speaker-id-v2`): the
  default speaker model, with a CPU build for other phones. See
  [docs/speaker_embedding.md](./docs/speaker_embedding.md).

### ASR API

- `ASREngine` and `ASRStream` (Kotlin and Flutter) and
  `TSASREngine` (Flutter): transcribe a clip, caption live audio
  you push, or let the SDK own the microphone, voice activity and
  turn ends. Results carry word timestamps (measured on Whisper),
  the detected language and, on request, speaker labels. See
  [docs/asr.md](./docs/asr.md).
- The voice agent runs its speech recognition on the same engine.
- Saved voices from another speaker model no longer fail a speaker
  session: they go unnamed until saved again with the current model.

### Voice agent

- Phonon and Pocket TTS can be the agent's voice: it starts `tts`
  with the type the SDK pins for that repo (Kotlin
  `tts_model_type` overrides it).
- `unspoken_tags` (Kotlin): reply text inside the named tags is
  shown and not spoken, e.g. a drafted email.

### Language and vision models

- **Up to 32768 tokens of context** for LFM2.5, LFM3, LFM2.5-VL and
  Gemma 4: pass `n_ctx` in the `start_model` config. The default
  stays 4096. See [docs/llm.md](./docs/llm.md) and
  [docs/vlm.md](./docs/vlm.md).
- **Prompt cache.** The system prompt and tools are processed once
  and kept across conversations and app restarts, so the first
  reply of a new conversation starts sooner. On by default; set
  `prompt_cache: false` in the start config to turn it off.
- **Gemma 4 chat.** A Gemma 4 handle takes the LLM chat request
  (`messages`, `tools`, thinking), images included, so it calls
  tools and keeps history like the language models. The voice agent
  can use Gemma 4 as its on-device LLM.
- **VLM conversations.** `messages` on LFM2.5-VL and Gemma 4 carry
  the earlier turns: each image is encoded once and the earlier
  turns stay processed, so a follow-up costs only its new tokens.
  See [docs/vlm.md](./docs/vlm.md).
- Gemma 4 no longer fails on prompts of about 1100 tokens.

### Loading and storage

- **`delete_model(engines_path)`** (Kotlin) removes every installed
  copy of a model repo and returns the bytes freed. See
  [docs/model_management.md](./docs/model_management.md#reclaiming-space).
- **`start_model` can be cancelled**: `cancel_start_model` in
  Flutter, or cancel the calling coroutine in Kotlin. The partial
  download is kept, and the next start resumes it.
- `start_model` returns as soon as the model is ready; it no longer
  waits for a network report.
- **Shared models.** Several owners can hold one running model:
  Kotlin `start_model` / `stop_model` take `owner =`, and the model
  unloads when its last owner stops. The voice agent and
  `ASREngine` hold their models under their own owners, so stopping
  one leaves a model the other still uses loaded. See
  [Starting a name that is already running](./docs/README.md#starting-a-name-that-is-already-running).

### Runtime

- Every NPU model now runs on TheStage's NPU runtime, and the
  smaller models on ONNX Runtime on the CPU. The app no longer
  needs the Qualcomm QNN runtime or Qualcomm's Maven repository,
  and `TheStageCore.aar` is about a third smaller.
- Whisper, NeuTTS, EmbeddingGemma, Nemotron diarization,
  MobileCLIP2 and the wake word move to new NPU builds, one build
  for all four supported chips.

## Upgrading from 1.1.x

- **Dependencies.** Remove the Qualcomm QNN runtime dependency
  (group `com.qualcomm.qti`) and the Qualcomm Maven repository from
  your app, and declare
  `com.microsoft.onnxruntime:onnxruntime-android:1.27.0` from Maven
  Central (see the README's setup section).
- **One download per changed model.** Whisper, NeuTTS,
  EmbeddingGemma, Nemotron diarization, MobileCLIP2 and the wake
  word download their new build once, on the first load after the
  upgrade.
- **Whisper streaming moved to the ASR API.**
  `TheStageAI.open_asr_streamer`, and `infer_stream` with
  `stream_append` / `stream_finish` on a Whisper model, are
  removed. Use `ASREngine.open_stream` (Kotlin) or `ASRStream.open`
  (Flutter). `stream_append` still drives diarization.
- **Starting a running name.** Starting a different model under a
  name that is already running throws the new
  `ModelManagerError.ModelNameConflict`; stop the running one first
  or use another name. Starting the same model with another
  `config` reloads it unless another owner holds it. Kotlin code
  with an exhaustive `when` over `ModelManagerError` and no `else`
  branch needs a new branch.
- **Speaker model.** The default speaker model (the voice agent,
  `ASREngine` speakers) is `TheStageAI/speaker-id-v2`, the same
  ReDimNet2 weights as `TheStageAI/redimnet2`, which stays pinned
  for apps that name it.

## Binary

| file | sha256 |
|---|---|
| `TheStageCore.aar` | `69999785fbbe9646c38dd23363253b75c6dbf64f5aaaba91264634b77ecdb5ba` |

## Models

Each model is pinned to the revision tested with this release, and
the SDK resolves it automatically: a request with an empty
`revision` downloads exactly that commit.

## Verify

```bash
shasum -a 256 TheStageCore.aar
```

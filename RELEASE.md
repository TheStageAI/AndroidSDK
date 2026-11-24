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

Every repo the SDK resolves by default, at the commit this build
pins. A request with an empty `revision` downloads exactly this
commit.

| `model_type` | repo | revision | bundles |
|---|---|---|---|
| `whisper` | `TheStageAI/thewhisper-large-v3-turbo` | `ca7aeea2c21f3a56317d61b0223ce2fe6a04da3f` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `qwen3-asr` | `TheStageAI/Qwen3-ASR-0.6B` | `67e6e1637f4ec99c4618eec7bad398e6117c4535` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `neutts` | `TheStageAI/neutts-nano-multilingual` | `c6f9fc154ecdc83374a244fe99b4a3d8c694549a` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `neutts` | `TheStageAI/neutts-multilingual` | `4e64168986d1d70fa3f2e9b3012525bf5508654c` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `neutts` | `TheStageAI/neutts` | `9729342c74d2e1c589c3916eb5f43f5c4c7547c9` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `phonon` | `TheStageAI/phonon-31m-en` | `da8ec7f56d81146acb36179ac59944d81dab759f` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `pocket-tts` | `TheStageAI/pocket-tts-18m-en` | `e29ab20c3c73b5ea019f9813a8d194da9c3b40f5` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `pocket-tts` | `TheStageAI/pocket-tts-100m-fr` | `82781e255ba5a2657290939a6e632af58712f4fd` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `pocket-tts` | `TheStageAI/pocket-tts-100m-de` | `0c111f379a2b432ac41fcf25b075f6ffb94c3b61` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `pocket-tts` | `TheStageAI/pocket-tts-100m-it` | `0e07c38bf2857e926777caf35f508539e4c50241` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `pocket-tts` | `TheStageAI/pocket-tts-100m-es` | `649eee024d3913bbf04186c526a5eb98fa079d3b` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `pocket-tts` | `TheStageAI/pocket-tts-100m-pt` | `c958191a8bcaba3fb104c56d8e8957d16fd8a9b4` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `pocket-tts` | `TheStageAI/pocket-tts-100m-nl` | `b5f6930ef6de6fbdcf104f47a6ae9b4580ffeea7` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `pocket-tts` | `TheStageAI/pocket-tts-100m-ja` | `dd78cd20012ec674b2c785852242be6459849e62` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `pocket-tts` | `TheStageAI/pocket-tts-100m-zh` | `cc089f5b3d3e0166f5da2f02eb1ca3f94645d151` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `pocket-tts` | `TheStageAI/pocket-tts-100m-ko` | `d75454d53362bbb19e1e32f259e4a634f53d2dc1` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `pocket-tts` | `TheStageAI/pocket-tts-100m-hi` | `3ac861ef0003ae6dbede1b99d6155df4efc6e664` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `pocket-tts` | `TheStageAI/pocket-tts-100m-pl` | `82c0b980066cf423a1a3ad352f893d171074e26d` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `pocket-tts` | `TheStageAI/pocket-tts-100m-tr` | `74e16109ef4fe8d18624a427450b3e4d48f68671` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `pocket-tts` | `TheStageAI/pocket-tts-100m-el` | `1ebe80b7e75fdb1b252b2887a4361d84aebfb4e3` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `pocket-tts` | `TheStageAI/pocket-tts-100m-ru` | `50534572a0b5fd36909874887944fa1bf55cd5c3` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `silero-vad` | `TheStageAI/silero-vad` | `ccbd42d0cef78a3e5de88ca6ab912ea6ad63a60d` | CPU |
| `wake-word` | `TheStageAI/wake-word` | `f5e45a9a3384fb5bcc7356d31a98d2ca49d4cf54` | CPU, 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `smart-turn` | `TheStageAI/smart-turn-v3` | `538b1c7dd2b5f307282a546a329987f9232e0d11` | CPU |
| `speaker-id` | `TheStageAI/redimnet2` | `df82f6452bfc8cd6cecf165a513cc1e55725b08f` | CPU |
| `speaker-id` | `TheStageAI/speaker-id-v2` | `3645f4871e698f12c60375a3154ca7f685a9c586` | CPU, 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `speaker-segmentation` | `TheStageAI/speaker-segmentation` | `ac71c82e9288a0ac153be2e1d49c762da2a81760` | CPU |
| `lfm2-vl` | `TheStageAI/LFM2.5-VL-450M` | `a75b7379a8e0bb465657b0cf4a4a1dd1d13153c0` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `mobile-clip-image` | `TheStageAI/MobileCLIP2-S0-image-encoder` | `a976c17322c3daf8e0caa2db5b70eda8420ca413` | CPU, 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `embedding-gemma` | `TheStageAI/embeddinggemma-300m` | `4c6f7f762282069ce8c1f59b678cb0b9d7c5fe32` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `embedding-gemma` | `TheStageAI/embeddinggemma-2` | `d9e4c1dd022974c338bafa133503a6fa0eb9c4ee` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `nemotron-diarization` | `TheStageAI/Nemotron-3-Diarization` | `3a954c8944085ad4492a5bd3d338f7de8f0d776c` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `the-stage-llm` | `TheStageAI/LFM2.5-230M` | `0057aa661a830470d6236c34e07ed476f1b949c8` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `the-stage-llm` | `TheStageAI/Qwen3.5-0.8B` | `09a94f8e5c22373d61f56ff72ae6d1f80f109f0e` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `the-stage-llm` | `TheStageAI/LFM2.5-350M` | `d1f846374a02c663823be81887f0a7fda5792bc4` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `the-stage-llm` | `TheStageAI/Qwen3.5-2B` | `1b4ad9d7cd09ce19664f95bf5bdac4e597454ed1` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `the-stage-llm` | `TheStageAI/LFM2.5-1.2B` | `9f0a758c82274f0fc0626fdbbd37d42c1bc00ca2` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `gemma4-vl` | `TheStageAI/gemma-4-E2B-it` | `0895e6e0421bc93a9148694c9dadb6f72db6b177` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `the-stage-llm` | `TheStageAI/LFM3-1.7B` | `a5c349bf2d1d27fb3ab5f049112e7361de3eadcb` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `the-stage-llm` | `TheStageAI/Qwen3.5-4B` | `89edfd01afe727e1c0dfd9758c4aedce13f1df20` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `the-stage-llm` | `TheStageAI/Qwen3.5-9B` | `6356780bce2a0f83e446d1d352c443495db71e59` | 8 Elite, 8 Elite Gen 5 |
| `lfm2-vl` | `TheStageAI/LFM2.5-VL-1.6B` | `459eb2c7539d382934aed42ad0c00dcc629c47bf` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `glinerel` | `TheStageAI/GLiNEREL-72m` | `4a87f6cce14c4fa07a4b256c06e1de2a86f23c84` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |

## Verify

```bash
shasum -a 256 TheStageCore.aar
```

# TheStage Android SDK 1.1.0

Pin this tag; the examples and the Flutter dependency use
`ref: v1.1.0`.

## What's new since 1.0.1

- **On-device chat LLMs** on TheStage's own Snapdragon NPU runtime:
  LFM2.5 (230M, 350M, 1.2B), LFM3-1.7B and Qwen3.5 (0.8B, 2B, 4B, and
  9B on 8 Elite and 8 Elite Gen 5 only),
  with streaming, multi-turn history that reuses the KV cache, MTP and
  thinking — see [docs/llm.md](./docs/llm.md). Qwen3-0.6B, listed as
  coming soon in 1.0.1, does not ship; use Qwen3.5-0.8B.
- **Tool calling** for the on-device LLMs (LFM2.5, LFM3, Qwen3.5):
  `infer_stream(..., tools)` runs your tools and continues the reply;
  built-in tools (weather, time, web search, Wikipedia, calculator,
  phone actions); the voice agent calls them mid-reply (`llm_tools`)
  — see [docs/llm.md](./docs/llm.md). The VLMs take no tools.
- **VLM**: LFM2.5-VL-450M, LFM2.5-VL-1.6B and Gemma 4 E2B (with MTP
  and thinking), images + prompt → text —
  see [docs/vlm.md](./docs/vlm.md).
- **TTS**: `neutts-nano-multilingual` (9 languages, smaller and faster)
  and the English-only `neutts`; your own voice packs (`voice_dir`);
  a startup chunk ramp (`chunk_frames_schedule`, default 8-12-20) for
  a faster first audio — see [docs/tts.md](./docs/tts.md).
- **Speaker diarization** — see [docs/diarization.md](./docs/diarization.md).
- **Voice agent**: speaker verification (`speaker_id`,
  `enroll_speaker`), speaker-verified wake-word starts
  (`turn_start_mode`), voice packs (`tts_voice_dir`) and the new
  on-device LLMs (`llm_provider = "local"`).
- **Examples**: `tutor_tts` (start here) and `tutor_small_llms` are
  new. `tts_front_stream` is removed; `tutor_tts` covers streaming TTS.
- The voice-agent examples need Flutter 3.38 (Dart 3.10.7+).

## Binary

| file | sha256 |
|---|---|
| `TheStageCore.aar` | `6bed8efc0e68ca4494c9006b94d54058dbc5245e58b3eb6d86b6fd961ab76840` |
| `onnxruntime-android.aar` | `d5fb3d4277e7717f7f2b8ecd5b4090946e3355dbde88d1e5a059a6c15fdb1d69` |

## Models

Every repo the SDK resolves by default, at the commit this build
pins. A request with an empty `revision` downloads exactly this
commit.

| `model_type` | repo | revision | bundles |
|---|---|---|---|
| `whisper` | `TheStageAI/thewhisper-large-v3-turbo` | `ca51a6fed4e2b42efbb3dd5c61ac4276336f4cd8` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `neutts` | `TheStageAI/neutts-nano-multilingual` | `83085448f37fec487f2d3f6659763bc2e87c1d29` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `neutts` | `TheStageAI/neutts-multilingual` | `42dba76dce47025f744e053bd53b98e3de6730bd` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `neutts` | `TheStageAI/neutts` | `af0e1fab60eed35b89f0d407b3e6d359e2c9154c` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `silero-vad` | `TheStageAI/silero-vad` | `ccbd42d0cef78a3e5de88ca6ab912ea6ad63a60d` | CPU |
| `wake-word` | `TheStageAI/wake-word` | `d0119e4cbd1652430464243eb2248f22e5cd51b2` | CPU, 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `smart-turn` | `TheStageAI/smart-turn-v3` | `538b1c7dd2b5f307282a546a329987f9232e0d11` | CPU |
| `speaker-id` | `TheStageAI/redimnet2` | `df82f6452bfc8cd6cecf165a513cc1e55725b08f` | CPU |
| `speaker-segmentation` | `TheStageAI/speaker-segmentation` | `ac71c82e9288a0ac153be2e1d49c762da2a81760` | CPU |
| `lfm2-vl` | `TheStageAI/LFM2.5-VL-450M` | `a75b7379a8e0bb465657b0cf4a4a1dd1d13153c0` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `mobile-clip-image` | `TheStageAI/MobileCLIP2-S0-image-encoder` | `c4a5c5ce5886773e2c1cc1efc3cb53c30dffe508` | CPU, 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `embedding-gemma` | `TheStageAI/embeddinggemma-300m` | `40f04233cd34443ef3428af3154b11464b6ad3e5` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `nemotron-diarization` | `TheStageAI/Nemotron-3-Diarization` | `88909716eb8f13acc03bc7c27661797d3f7a11a4` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `the-stage-llm` | `TheStageAI/LFM2.5-230M` | `0057aa661a830470d6236c34e07ed476f1b949c8` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `the-stage-llm` | `TheStageAI/Qwen3.5-0.8B` | `09a94f8e5c22373d61f56ff72ae6d1f80f109f0e` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `the-stage-llm` | `TheStageAI/LFM2.5-350M` | `d1f846374a02c663823be81887f0a7fda5792bc4` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `the-stage-llm` | `TheStageAI/Qwen3.5-2B` | `1b4ad9d7cd09ce19664f95bf5bdac4e597454ed1` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `the-stage-llm` | `TheStageAI/LFM2.5-1.2B` | `9f0a758c82274f0fc0626fdbbd37d42c1bc00ca2` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `gemma4-vl` | `TheStageAI/gemma-4-E2B-it` | `0895e6e0421bc93a9148694c9dadb6f72db6b177` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `the-stage-llm` | `TheStageAI/LFM3-1.7B` | `a5e87f3bb8a8e936364e3b70ad38a5bea1dedee2` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `the-stage-llm` | `TheStageAI/Qwen3.5-4B` | `89edfd01afe727e1c0dfd9758c4aedce13f1df20` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `the-stage-llm` | `TheStageAI/Qwen3.5-9B` | `6356780bce2a0f83e446d1d352c443495db71e59` | 8 Elite, 8 Elite Gen 5 |
| `lfm2-vl` | `TheStageAI/LFM2.5-VL-1.6B` | `459eb2c7539d382934aed42ad0c00dcc629c47bf` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |

## Verify

```bash
shasum -a 256 TheStageCore.aar onnxruntime-android.aar
```

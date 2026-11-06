# TheStage Android SDK 1.1.1

Pin this tag; the examples and the Flutter dependency use
`ref: v1.1.1`.

## What's new since 1.1.0

- **Faster LFM3-1.7B prompts on every supported chip.** The SDK now
  pins a newer build of the same checkpoint: prompt processing is
  about 2.4x faster on Snapdragon 8 Elite and about 1.5x faster on
  8 Gen 3, with the same answers. Apps that pass an empty `revision`
  get it automatically; an app that already has LFM3 installed keeps
  serving it until it calls
  `prefetch_model(..., replace_existing = true)`.
- **Model removal waits for loads.** `remove_model` and
  `reset_models` now also refuse while a model is still starting or
  downloading (`ModelManagerError.ModelInUse` with `loading = true`).
  While a removal runs,
  `start_model` and `prefetch_model` for the affected model fail with
  the new `ModelManagerError.StorageBusy`; retry once the removal
  returns. In Flutter these are `ModelInUseException` (`MODEL_IN_USE`)
  and `StorageBusyException` (`STORAGE_BUSY`), both
  `PlatformException`s, so existing `on PlatformException` handlers
  still catch them. See [docs/model_management.md](./docs/model_management.md).
- **No AndroidX dependency.** The SDK no longer needs `androidx.core`
  at runtime; a native Kotlin app needs only the dependencies listed
  in the README.

### Behaviour changes

- `reset_models()` refuses while a download is in flight, instead of
  aborting it. Stop or let the download finish first.
- `ModelManagerError` has a new subclass, `StorageBusy`. Kotlin code
  with an exhaustive `when` over it and no `else` branch needs a new
  branch.

## Binary

| file | sha256 |
|---|---|
| `TheStageCore.aar` | `a215ac81a7dfa53966bb03aef3d0deea15e277aa376389f58fd0e72308b5128b` |
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
| `the-stage-llm` | `TheStageAI/LFM3-1.7B` | `a5c349bf2d1d27fb3ab5f049112e7361de3eadcb` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `the-stage-llm` | `TheStageAI/Qwen3.5-4B` | `89edfd01afe727e1c0dfd9758c4aedce13f1df20` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |
| `the-stage-llm` | `TheStageAI/Qwen3.5-9B` | `6356780bce2a0f83e446d1d352c443495db71e59` | 8 Elite, 8 Elite Gen 5 |
| `lfm2-vl` | `TheStageAI/LFM2.5-VL-1.6B` | `459eb2c7539d382934aed42ad0c00dcc629c47bf` | 8 Gen 2, 8 Gen 3, 8 Elite, 8 Elite Gen 5 |

## Verify

```bash
shasum -a 256 TheStageCore.aar onnxruntime-android.aar
```

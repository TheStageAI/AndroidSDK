# Third-Party Notices

The TheStage Android SDK depends on, links against, or ships alongside
the third-party components listed below. Each remains under its own
license; the license identifier and a short note on how the component
is used are given for each. Where a license could not be positively
confirmed at authoring time it is marked **(verify)** and should be
checked against the component's own repository before distribution.

The SDK's own binaries (`TheStageCore.aar`, `libStagenie.so`, model
engines) are covered by the top-level [LICENSE](./LICENSE).

---

## Runtime dependencies bundled or linked by the SDK

### ONNX Runtime
- **License:** MIT
- **Use:** `onnxruntime-android.aar` — the QNN-EP-enabled ONNX Runtime
  the core links against for on-device inference. Built from source
  with the Qualcomm QNN execution provider. ONNX Runtime bundles its
  own third-party components (FlatBuffers, protobuf, nsync, etc.),
  each under its own permissive license — see ONNX Runtime's
  `ThirdPartyNotices.txt`.
- **Project:** https://github.com/microsoft/onnxruntime

### Hugging Face `tokenizers` (Rust)
- **License:** Apache-2.0
- **Use:** the native Rust tokenizer layer (`libqlip_tokenizers.so` /
  the JNI tokenizer bridge) used to tokenize prompts on-device. This
  library statically links the crate's transitive Rust dependencies,
  which are individually licensed under MIT or Apache-2.0 (see
  `cargo tree` / the crate's `Cargo.lock` for the full graph).
- **Project:** https://github.com/huggingface/tokenizers

### pffft (PrettyFastFFT)
- **License:** BSD-3-Clause-style (FFTPACK-derived); © Julien Pommier
- **Use:** vendored (`third_party/pffft`) and statically linked into
  `libqlip_native.so` for the NeuCodec inverse real-FFT (ISTFT).
- **Project:** https://bitbucket.org/jpommier/pffft

### LLVM `libc++` (`libc++_shared.so`)
- **License:** Apache-2.0 WITH LLVM-exception
- **Use:** the C++ standard library shared object bundled with the
  native runtimes (NDK `libc++_shared.so`).
- **Project:** https://github.com/llvm/llvm-project (`libcxx`)

### Gson
- **License:** Apache-2.0
- **Use:** JSON serialization for the inference API and metadata
  parsing. Declared as a transitive dependency of the core.
- **Project:** https://github.com/google/gson

### OkHttp
- **License:** Apache-2.0
- **Use:** HTTPS transport for token validation and HuggingFace engine
  downloads. Declared as a transitive dependency of the core.
- **Project:** https://github.com/square/okhttp

### kotlinx.coroutines
- **License:** Apache-2.0
- **Use:** asynchronous / streaming inference plumbing. Declared as a
  dependency of the core.
- **Project:** https://github.com/Kotlin/kotlinx.coroutines

### Okio
- **License:** Apache-2.0
- **Use:** I/O buffering underneath OkHttp; pulled in transitively.
- **Project:** https://github.com/square/okio

### AndroidX Core (`androidx.core:core-ktx`)
- **License:** Apache-2.0
- **Use:** Android platform Kotlin extensions used by the core module.
- **Project:** https://developer.android.com/jetpack/androidx

---

## Proprietary runtime (not redistributed by this SDK)

### Qualcomm QNN / QAIRT runtime
- **License:** Proprietary — provided by Qualcomm under their own
  license terms. **Not redistributed by this SDK.**
- **Use:** the Hexagon NPU (HTP) backend. The signed per-SoC QNN HTP
  skel/stub libraries are pulled by the consumer app from Qualcomm's
  public Maven repository (`com.qualcomm.qti:qnn-runtime:2.42.0`). The
  four Genie backend libraries (`libQnnGenAiTransformer.so`,
  `libQnnGenAiTransformerCpuOpPkg.so`,
  `libQnnGenAiTransformerModel.so`, `libQnnCpu.so`) are **not** on
  Maven and are **not** shipped here — the consumer must copy them
  from their own Qualcomm QAIRT 2.42 SDK install (see the top-level
  `README.md` and `scripts/setup.sh`). Your use of these libraries is
  governed by Qualcomm's license, not by this SDK's license.
- **Project:** https://qpm-download.qualcomm.com / Qualcomm AI Engine
  Direct (QAIRT) SDK

---

## Optional, fetched on demand (NOT bundled)

### espeak-ng
- **License:** GPLv3
- **Use:** the phonemizer for the NeuTTS **nano** (English) path only.
  It is **not bundled** in this distribution. It is fetched on demand
  by `scripts/setup.sh --espeak` and only when you build a
  neutts-nano app. The multilingual TTS model and all shipped example
  apps do **not** use it, so nothing GPL-licensed is distributed with
  or linked into the default SDK binaries.
- **Project:** https://github.com/espeak-ng/espeak-ng

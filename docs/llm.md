# LLM (Language Model)

> **Coming soon.** The on-device LLM bundles (`Qwen3-0.6B`, `LFM2.5-230M`)
> are not published yet — this API and its contract are documented ahead of
> that release. The `voice_agent` example uses a remote (OpenAI-compatible)
> LLM today; its on-device (`local`) provider is shown but disabled.

On-device language model inference with batch and token-by-token
streaming. `TheStageLLM` wraps Qwen3 / LFM2.5 chat
models with KV cache, chat-template rendering, and stop-token policy.

Flutter consumers go through the singleton `start_model` +
`infer` / `infer_stream` (JSON) path — there is no direct LLM
constructor on Dart. Both surfaces share the same on-disk cache and
the same response shape.

## Basic Usage

**Kotlin** — via the singleton (recommended; auto-downloads the bundle):

```kotlin
// build.gradle.kts: implementation(files("libs/TheStageCore.aar"))
import ai.thestage.qlip.TheStageAI

// Inside a coroutine (initialize / start_model / infer are suspend).
TheStageAI.registerContext(context)
TheStageAI.initialize(api_token = "your-api-token")

TheStageAI.start_model(
    model_name = "llm",
    engines_path = "TheStageAI/Qwen3-0.6B"   // HF repo id, or a local dir
)

val result = TheStageAI.infer(
    model_name = "llm",
    input_json = mapOf(
        "prompt" to "What is 2+2?",
        "system_prompt" to "You are a helpful assistant.",
        "max_new_tokens" to 64
    )
)
println(result[0]["text"])
```

You can also construct `TheStageLLM` directly against a **local**
(already-downloaded) engines directory. Unlike the singleton, the
direct constructor does not fetch from HuggingFace — pull the bundle
first with `prefetch_model` (see [Prefetch Engines](#prefetch-engines)),
then hand it the local path:

```kotlin
import ai.thestage.qlip.models.llm.TheStageLLM

val dir = TheStageAI.prefetch_model(repo_id = "TheStageAI/Qwen3-0.6B")

val llm = TheStageLLM(engines_path = dir)     // local dir

val out = llm.infer(
    prompt = "List 20 facts about London.",
    system_prompt = "You are a helpful assistant.",
    max_new_tokens = 256
)
println(out.text)                              // out.tokens_per_second, ...
```

`infer` / `infer_stream` take `prompt`, `system_prompt`,
`max_new_tokens`, `seed`, and optional per-call sampling overrides:
`temperature`, `top_k`, `top_p`, `min_p`, and `repetition_penalty`.
Each bundle ships a tuned sampling preset in its config; every override
you omit keeps that preset, so a call passing none reproduces the
bundle's defaults. Pass a field to override it for that call only —
later calls are unaffected:

```kotlin
import ai.thestage.qlip.pipelines.SamplingParams

val out = llm.infer(
    prompt = "Write a haiku about the sea.",
    max_new_tokens = 64,
    sampling = SamplingParams(
        temperature = 0.8f,
        top_k = 40,
        repetition_penalty = 1.1f,
    ),
)
```

**Flutter** — JSON path:

```dart
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');

await TheStageFlutterSDK.start_model(
  model_name: 'llm',
  engines_path: 'TheStageAI/Qwen3-0.6B',
);

final result = await TheStageFlutterSDK.infer(
  model_name: 'llm',
  input_json: {
    'prompt': 'What is 2+2?',
    'system_prompt': 'You are a helpful assistant.',
    'max_new_tokens': 64,
  },
);
print(result[0]['text']);
```

## Inputs / Outputs

| Direction | Type | Description |
|---|---|---|
| input  `prompt` | `String` | The user message. |
| input  `system_prompt` | `String?` | Optional system message; defaults to the bundle's `default_system_prompt`. |
| input  `max_new_tokens` | `Int` (default 512) | Hard cap on generated tokens — output is truncated at this length. |
| input  `seed` | `Long?` | Deterministic sampling seed. |
| input  `temperature` | `Float?` | Softmax temperature. Omit to keep the bundle preset. |
| input  `top_k` | `Int?` | Top-k truncation. Omit to keep the bundle preset. |
| input  `top_p` | `Float?` | Nucleus (top-p) threshold. Omit to keep the bundle preset. |
| input  `min_p` | `Float?` | Min-p threshold. Omit to keep the bundle preset. |
| input  `repetition_penalty` | `Float?` | Penalty on repeated tokens. Omit to keep the bundle preset. |
| input  `min_new_tokens` | `Int?` | Suppress EOS until at least N tokens are generated. **Opt-in, requires a patched runtime** (see below); omit on stock builds. |
| input  `enable_thinking` | `Bool` (default `true`) | Qwen-3 reasoning toggle. `false` skips the `<think>…</think>` block; ignored by non-reasoning families. |
| output `LlmResult.text` | `String` | Decoded response. |
| output `LlmResult.prompt_tokens` / `generated_tokens` | `Int` | Token counts. |
| output `LlmResult.tokens_per_second` | `Double` | Decode speed. |
| output `LlmResult.time_to_first_token` / `total_seconds` | `Double` | Latency breakdown. |
| output `LlmResult.stop_reason` | `String` | `"eos"` / `"max_new_tokens"` / `"stop_sequence"`. |

Sampling defaults are **per-model**: each bundle ships a tuned preset.
Any sampling field you omit keeps that preset, so you only set the
knobs you want to change — a call with no sampling fields reproduces
the bundle's shipped defaults exactly. In JSON, pass the keys inside
`input_json`; from Kotlin, pass a `SamplingParams`.

The native `TheStageLLM.infer(...)` additionally accepts
`stop_sequences: List<String>` — generation's decoded text is cut at the
first matching substring (applied on the one-shot path only, matching the
streaming/non-streaming split on other platforms).

### Minimum length (`min_new_tokens`)

`min_new_tokens` forces the model to emit at least N tokens before an
end-of-sequence token can stop generation — useful when you need a
minimum response length and want to prevent an early EOS. Pass it in
`input_json` (JSON path) or on `SamplingParams` (`min_new_tokens: Int?`).

This knob is **opt-in and requires a runtime that supports minimum
length enforcement.** On a stock build the underlying sampler rejects
it, so the SDK only forwards it when you set it to a value `> 0` — a
call that omits it is unaffected. Treat it as a no-op on runtimes that
don't support it, and don't rely on it for correctness; enforce a hard
floor in your own app logic if you must guarantee a minimum.

```kotlin
val out = llm.infer(
    prompt = "Summarize the plot in a full paragraph.",
    max_new_tokens = 256,
    sampling = SamplingParams(min_new_tokens = 32),
)
```

```dart
final result = await TheStageFlutterSDK.infer(
  model_name: 'llm',
  input_json: {
    'prompt': 'Summarize the plot in a full paragraph.',
    'max_new_tokens': 256,
    'min_new_tokens': 32,
  },
);
```

## Streaming

Token-by-token generation. Each chunk before the terminal sentinel
carries one delta of text; the final chunk has `is_final == true` and
the full per-call metrics.

**Kotlin** — `infer_stream` returns a Kotlin `Flow<LlmStreamChunk>`:

```kotlin
llm.infer_stream(
    prompt = "Tell me a story.",
    max_new_tokens = 512
).collect { chunk ->
    if (chunk.is_final) {
        val tps = chunk.tokens_per_second ?: 0.0
        println("\n--- $tps tok/s ---")
    } else {
        print(chunk.text)
    }
}
```

**Flutter:**

```dart
final stream = TheStageFlutterSDK.infer_stream(
  model_name: 'llm',
  input_json: {
    'prompt': 'Tell me a story.',
    'max_new_tokens': 512,
  },
);

await for (final chunk in stream) {
  if (chunk['is_final'] == true) {
    final tps = chunk['tokens_per_second'] as double? ?? 0;
    print('\n--- $tps tok/s ---');
  } else {
    final delta = chunk['delta'] as String?;
    if (delta != null) stdout.write(delta);
  }
}
```

## Supported Models

| Model | HF repo | Parameters | Chat template |
|-------|---------|-----------:|---------------|
| Qwen3-0.6B | `TheStageAI/Qwen3-0.6B` | 0.6B | Qwen3 |
| LFM2.5-230M | `TheStageAI/LFM2.5-230M` | 230M | LFM2 |

The bundle's `engines_path` accepts either a HuggingFace repo id (for
`start_model`) or a local directory. The chat template, EOS / stop
tokens and KV-cache horizon all come from the bundle — you don't pick
them.

## Singleton API (`TheStageAI`)

Use this when you want lifecycle (`stop_model`), JSON dispatch
(`infer(model_name, input_json)`), auto-download, or are driving the
SDK from Flutter. Both flows share the same on-disk cache. `TheStageAI`
is a Kotlin `object` (singleton); its methods are `suspend`.

```kotlin
TheStageAI.start_model(
    model_name = "llm",
    engines_path = "TheStageAI/Qwen3-0.6B"
)

val json = TheStageAI.infer(
    model_name = "llm",
    input_json = mapOf(
        "prompt" to "What is 2+2?",
        "system_prompt" to "You are a helpful assistant.", // optional
        "max_new_tokens" to 256,                            // optional
        "seed" to 42L                                       // optional
    )
)
val text = json[0]["text"] as String
```

JSON streaming yields typed `InferenceStreamChunk` values — `delta`
carries each token's text:

```kotlin
TheStageAI.infer_stream(
    model_name = "llm",
    input_json = mapOf("prompt" to "Tell me a story.", "max_new_tokens" to 512)
).collect { chunk ->
    if (!chunk.is_final && chunk.delta != null) print(chunk.delta)
    if (chunk.is_final && chunk.tokens_per_second != null) {
        println("\n--- ${chunk.tokens_per_second} tok/s ---")
    }
}
```

JSON response keys (matches the table above): `text`, `prompt_tokens`,
`generated_tokens`, `prefill_seconds`, `decode_seconds`,
`tokens_per_second`, `time_to_first_token`, `total_seconds`,
`stop_reason`.

The JSON path is single-turn. For multi-turn chat history use the
direct `TheStageLLM` API; chat templates are rendered for you.

The Flutter `TheStageFlutterSDK.infer` / `infer_stream` calls hit this
exact JSON path, so the response keys above apply unchanged on Dart.

## Full Constructor

```kotlin
val llm = TheStageLLM(
    engines_path = dir,                    // local (prefetched) dir
    device = "npu",                        // "npu" | "gpu" | "cpu" (see note)
    chat_template_override = null,         // null = use the bundle's
    system_prompt_override = null,         // null = use the bundle's
    eos_token_id_override = null           // null = use the spec's
)
```

> `device` is accepted so the Kotlin and Flutter/JSON call sites match,
> but backend routing (framework + device) is authoritative in the
> bundle's
> `metadata.json`, so an override here is a no-op by design. The
> KV-cache horizon likewise comes from the bundle spec.

The direct constructor loads from a **local** directory only — it does
not download. Use `TheStageAI.prefetch_model(...)` (or `start_model`)
to fetch the bundle first. `TheStageAI.initialize(...)` must have
succeeded before either call.

## Load Progress

The direct `TheStageLLM` constructor loads from a local dir and emits
no progress. Download / extract / load progress is reported through the
singleton and Flutter entry points via an optional `on_load_progress`
handler that fires through four phases with a monotonic `fraction` in
`0.0 .. 1.0`:

```kotlin
TheStageAI.start_model(
    model_name = "llm",
    engines_path = "TheStageAI/Qwen3-0.6B",
    on_load_progress = { p ->
        // p.phase ∈ { DOWNLOADING, EXTRACTING, LOADING, READY }
        // p.fraction in 0.0 .. 1.0, monotonic across phases
        println("[${p.model}] ${p.phase} ${(p.fraction * 100).toInt()}%")
    }
)
```

Cache hits skip `DOWNLOADING` / `EXTRACTING` and emit only `LOADING`
followed by `READY`. Failed loads do not emit `READY`. The same
`on_load_progress` parameter is accepted by
`TheStageAI.prefetch_model(...)`.

For the full event contract see
[Load Progress in the index](./README.md#load-progress).

**Flutter:** progress events for every active `start_model` call are
multiplexed through a single global stream:

```dart
TheStageFlutterSDK.on_progress.listen((event) {
  if (event['model_name'] != 'llm') return;
  final phase    = event['phase']    as String?;   // downloading | extracting | loading | ready
  final fraction = event['progress'] as double?;   // 0.0 ... 1.0, monotonic
  print('[llm] $phase ${(fraction ?? 0) * 100}%');
});

await TheStageFlutterSDK.start_model(
  model_name: 'llm',
  engines_path: 'TheStageAI/Qwen3-0.6B',
);
```

## Prefetch Engines

If you'd rather download bundles ahead of time (e.g. on a "Download
models" screen) so a later construction is a pure local load, use
`prefetch_model`:

```kotlin
val engines_dir = TheStageAI.prefetch_model(
    repo_id = "TheStageAI/Qwen3-0.6B"
)

// Later — instant load, no network:
val llm = TheStageLLM(engines_path = engines_dir)
```

You don't need to call `prefetch_model` before `start_model` — the
singleton pulls the bundle on demand and caches it. (The direct
`TheStageLLM` constructor, however, requires a local dir, so prefetch
first when using it.)

## Cleanup

`TheStageLLM` is a normal Kotlin object — call `close()` to release it.
When you used the singleton API:

```kotlin
TheStageAI.stop_model(model_name = "llm")
```

**Flutter:**

```dart
await TheStageFlutterSDK.stop_model(model_name: 'llm');
```

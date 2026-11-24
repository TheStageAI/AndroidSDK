# VLM (Vision-Language Model)

On-device image + text → text. `TheStageVLM` runs the vision encoder
and the language model entirely on the Snapdragon Hexagon NPU — hand
it one or more images and a prompt, get back a text answer. Batch and
token-by-token streaming share the same response shape as the
[LLM](./llm.md) path.

## Supported Models

| Model | HF repo | Size on disk | Context (tokens) | MTP | Thinking (default) |
|---|---|---:|---:|:---:|---|
| LFM2.5-VL-450M | `TheStageAI/LFM2.5-VL-450M` | 0.41 GB | 4096 (up to 32768) | — | — |
| LFM2.5-VL-1.6B | `TheStageAI/LFM2.5-VL-1.6B` | 1.33 GB | 4096 (up to 32768) | — | — |
| Gemma 4 E2B | `TheStageAI/gemma-4-E2B-it` | 1.97 GB | 4096 (up to 32768) | yes | yes (off) |

All three run on Snapdragon 8 Gen 2 (SM8550), 8 Gen 3 (SM8650),
8 Elite (SM8750) and 8 Elite Gen 5 (SM8850). Their `model_type` is
`lfm2-vl` (both LFM2.5-VL models) or `gemma4-vl` (Gemma 4); the SDK
resolves it from the repo id, so `start_model` needs only the repo; the
`model_name` you pick (`"vlm"` below) is your handle for later calls.

## Basic Usage

**Kotlin** — via the singleton:

```kotlin
import ai.thestage.qlip.TheStageAI

TheStageAI.registerContext(context)
TheStageAI.initialize(api_token = "your-api-token")

TheStageAI.start_model(
    model_name = "vlm",
    engines_path = "TheStageAI/LFM2.5-VL-450M",
)

val result = TheStageAI.infer(
    model_name = "vlm",
    input_json = mapOf(
        "image" to "/path/to/photo.jpg",
        "prompt" to "What is in this image?",
        "max_new_tokens" to 128,
    ),
)
println(result[0]["text"])
```

**Flutter** — JSON path:

```dart
await TheStageFlutterSDK.start_model(
  model_name: 'vlm',
  engines_path: 'TheStageAI/LFM2.5-VL-450M',
);

final result = await TheStageFlutterSDK.infer(
  model_name: 'vlm',
  input_json: {
    'image': '/path/to/photo.jpg',
    'prompt': 'What is in this image?',
    'max_new_tokens': 128,
  },
);
print(result[0]['text']);
```

## Inputs / Outputs

| Key | Type | Default | Description |
|---|---|---|---|
| `image` | `String?` | — | File path to the input image (JPEG, PNG, …). Omit for a text-only turn — see below. |
| `image_0`, `image_1`, … | `String` | — | Several images for one prompt, numbered from 0 with no gaps. When present they replace `image`. |
| `prompt` | `String` | required | Question / instruction. |
| `messages` | `List` | — | Earlier turns of the conversation, oldest first; see [Conversations](#conversations). |
| `tools` | `List` | — | Gemma 4: tools the model may call; see [Gemma 4 chat requests](#gemma-4-chat-requests). |
| `preset` | `String` | `"medium"` | How much detail the model sees (below). |
| `system_prompt` | `String?` | — | Optional system message. |
| `max_new_tokens` | `Int` | the bundle's (1024) | Cap on generated tokens. |
| `enable_thinking` | `Bool?` | the model's (off) | Gemma 4: reason before answering. Ignored by LFM2.5-VL. |
| `seed`, `temperature`, `top_k`, `min_p`, `repetition_penalty` | — | — | Accepted, and ignored: the models decode greedily. |
| output `text` | `String` | — | The generated answer. |

The result also carries `prompt_tokens`, `image_tokens` and
`gen_tokens`, and timings in milliseconds (`vision_ms`, `prompt_ms`,
`ttft_ms`, `decode_ms`) plus `decode_tps`, for diagnostics.

**`preset`:**

| Model | `"medium"` (default) | `"high"` | other values |
|---|---|---|---|
| LFM2.5-VL | one tile, resized to keep the image's aspect | a grid of tiles plus a thumbnail, for a large image: more detail, slower | — |
| Gemma 4 | up to 280 image tokens | the most the bundle's vision pass takes (280 on the published bundle, the same as `"medium"`) | `"low"` = up to 70 tokens; or the budget: `"70"`, `"140"`, `"280"` |

Fewer image tokens make the image pass and the prompt faster; more
let the model read finer detail (small text, distant objects). A
Gemma 4 budget is a maximum: an image uses fewer tokens when its
aspect ratio leaves part of the budget unused (`image_tokens` in the
result says how many).

### Text-only prompts

`image` is optional. A call with only `prompt` runs as a text-only
turn — the vision pass is skipped:

```kotlin
val out = TheStageAI.infer(
    model_name = "vlm",
    input_json = mapOf(
        "prompt" to "Background: … Now answer: name the capital " +
            "of France. One word.",
        "max_new_tokens" to 16,
    ),
)
```

Two limits worth knowing before you rely on it:

- **Quality is prompt-sensitive.** These are vision-first models. A
  question with surrounding context answers well; a bare one-line
  instruction can come back as a stray token. If you need dependable
  text generation, use a text [LLM](./llm.md) rather than this.
- **Nine languages (LFM2.5-VL):** English, Arabic, Chinese, French,
  German, Japanese, Korean, Portuguese, Spanish. Anything else is out
  of scope for both modalities.

## Conversations

Pass the earlier turns as `messages`, oldest first, and the new
question as `prompt` (with its `image`, if any):

```dart
final result = await TheStageFlutterSDK.infer(
  model_name: 'vlm',
  input_json: {
    'messages': [
      {'role': 'user', 'content': 'What is in this photo?',
       'image': '/path/to/photo.jpg'},
      {'role': 'assistant', 'content': 'A cat on a windowsill.'},
    ],
    'prompt': 'What color is it?',
  },
);
```

| Key in a message | Meaning |
|---|---|
| `role` | `"user"` or `"assistant"`; other roles are skipped |
| `content` | The turn's text |
| `image` / `images` | A user turn's image file, or a list of them |

Each image goes through the vision pass once and later turns reuse
it, and the model keeps the earlier turns processed between calls,
so a follow-up costs only its new tokens. Send the same history
again each turn, extended by the last exchange.

## Gemma 4 chat requests

Gemma 4 also takes the chat request of the [LLM](./llm.md) page: a
call with `messages` or `tools` runs as an LLM chat turn, with the
same keys and the same stream chunks (`text_delta`,
`thinking_delta`, `tool_call`, `tool_result`, `final`). Tool
calling, thinking and history then work as described in
[LLM → Tool calling](./llm.md), and a user message's `image` /
`images` are part of the turn. A `prompt` (and its `image`) next to
`messages` that do not end on a user turn is taken as the last user
turn. The LFM2.5-VL models take `messages` as history only; they do
not call tools.

## MTP and Thinking (Gemma 4)

Gemma 4 has both features of the [LLM](./llm.md#mtp-and-thinking)
models, and `start_model` reports them the same way under
`features`. MTP (its drafter) is on by default; turn it off with
`config: {'use_mtp': false}` at `start_model`. Thinking is off by
default; turn it on per request with `'enable_thinking': true` and a
larger `max_new_tokens`.

With thinking on, Gemma 4's reply carries its reasoning between its
own markers, and your app splits it:

```
<|channel>thought
The animal has whiskers and pointed ears ...<channel|>A cat sitting on a windowsill.
```

Everything between `<|channel>thought` and `<channel|>` is reasoning;
the answer follows `<channel|>`. See
[Thinking](./llm.md#thinking-enable_thinking) for the markers of the
other models.

The LFM2.5-VL models report both features as unsupported.

## Context size

Every model here opens with up to 32768 tokens of context with
`config = mapOf("n_ctx" to 32768)` (Dart: `config: {'n_ctx': 32768}`)
at `start_model`; without it, the table's 4096. It works as for the
[LLM](./llm.md#context-size-n_ctx) models: memory follows the
conversation, and decoding slows as it grows. How much of a long
context a model actually uses depends on the model; test the
lengths your app needs.

## Streaming

`infer_stream` streams text deltas exactly like the LLM path — each
chunk before the terminal one carries a `delta`; the final chunk has
`is_final == true`.

```dart
import 'dart:io';

final stream = TheStageFlutterSDK.infer_stream(
  model_name: 'vlm',
  input_json: {
    'image': '/path/to/photo.jpg',
    'prompt': 'Describe this scene in detail.',
    'max_new_tokens': 256,
  },
);

await for (final chunk in stream) {
  if (chunk['is_final'] == true) break;
  final delta = chunk['delta'] as String?;
  if (delta != null) stdout.write(delta);
}
```

Asking about the same image again (a follow-up question) reuses its
encoded rows, so only the first question pays for the image pass.

See [Streaming](./streaming.md) for the shared chunk contract and
[Model Management](./model_management.md) for loading the VLM's vision
encoder + decoder components independently.

## Cleanup

```dart
await TheStageFlutterSDK.stop_model(model_name: 'vlm');
```

## Example app

The VLM tab of `examples/engine_bench` loads either LFM2.5-VL
model and times image + prompt → text on the phone, and
`examples/voice_agent_custom_nodes` starts one to caption a picked
image while the voice agent is quiet, then stops it.

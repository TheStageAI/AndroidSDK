# LLM (Language Model)

On-device chat with batch and token-by-token streaming, and
[tool calling](#tool-calling). The whole model runs on the
Snapdragon Hexagon NPU; `TheStageLLM` renders each model's chat
template, applies its stop tokens, and keeps the conversation's KV
cache between turns.

Flutter consumers go through the singleton `start_model` +
`infer` / `infer_stream` (JSON) path — there is no direct LLM
constructor on Dart. Both surfaces share the same on-disk cache and
the same response shape.

## Supported Models

| Model | HF repo | Size on disk | Context (tokens) | MTP | Thinking (default) | Tools |
|---|---|---:|---:|:---:|---|:---:|
| LFM2.5-230M | `TheStageAI/LFM2.5-230M` | 0.26 GB | 4096 | yes | — | yes |
| LFM2.5-350M | `TheStageAI/LFM2.5-350M` | 0.32 GB | 4096 | yes | — | yes |
| LFM2.5-1.2B | `TheStageAI/LFM2.5-1.2B` | 1.05 GB | 4096 | yes | — | yes |
| LFM3-1.7B | `TheStageAI/LFM3-1.7B` | 1.46 GB | 4096 | yes | yes (on) | yes |
| Qwen3.5-0.8B | `TheStageAI/Qwen3.5-0.8B` | 0.39 GB | 8192 | — | yes (off) | yes |
| Qwen3.5-2B | `TheStageAI/Qwen3.5-2B` | 0.95 GB | 8192 | — | yes (off) | yes |
| Qwen3.5-4B | `TheStageAI/Qwen3.5-4B` | 2.10 GB | 8192 | — | yes (off) | yes |
| Qwen3.5-9B | `TheStageAI/Qwen3.5-9B` | 4.42 GB | 8192 | — | yes (off) | yes |

Each LLM publishes one NPU bundle that serves all four supported
Snapdragon chips: 8 Gen 2 (SM8550), 8 Gen 3 (SM8650), 8 Elite
(SM8750) and 8 Elite Gen 5 (SM8850). **Qwen3.5-9B ships only for
8 Elite and 8 Elite Gen 5**; on 8 Gen 2 and 8 Gen 3 its
`start_model` fails with an error naming the chip. Image + text
models are on the [VLM](./vlm.md) page.

The chat template, stop tokens, context size and per-call token cap
all come from the bundle — you don't pick them. **MTP** and
**thinking** are described under [MTP and Thinking](#mtp-and-thinking),
**tools** under [Tool calling](#tool-calling); `start_model` reports
all three for the model it loaded.

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
    engines_path = "TheStageAI/LFM2.5-1.2B"   // HF repo id, or a local dir
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

**Flutter** — JSON path:

```dart
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');

await TheStageFlutterSDK.start_model(
  model_name: 'llm',
  engines_path: 'TheStageAI/LFM2.5-1.2B',
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

You can also construct `TheStageLLM` directly against a **local**
(already-downloaded) engines directory. Unlike the singleton, the
direct constructor does not fetch from HuggingFace — pull the bundle
first with `prefetch_model` (see [Prefetch Engines](#prefetch-engines)),
then hand it the local path:

```kotlin
import ai.thestage.qlip.models.llm.TheStageLLM

val dir = TheStageAI.prefetch_model(repo_id = "TheStageAI/LFM2.5-1.2B")

val llm = TheStageLLM(engines_path = dir)     // local dir

val out = llm.infer(
    prompt = "List 20 facts about London.",
    system_prompt = "You are a helpful assistant.",
    max_new_tokens = 256
)
println(out.text)                              // out.tokens_per_second, ...
```

## Inputs / Outputs

| Direction | Type | Description |
|---|---|---|
| input  `prompt` | `String` | The user message. |
| input  `system_prompt` | `String?` | Optional system message; defaults to the bundle's. |
| input  `messages` | `List<{role, content}>?` | Multi-turn history, oldest first, ending with the new user turn; `role` is `user` or `assistant` (and `tool` with tools). Supersedes `prompt`. See [Multi-turn chat](#multi-turn-chat). |
| input  `tools` | `List<{name, description, parameters}>?` | Functions the model may call. See [Tool calling](#tool-calling). |
| input  `max_tool_rounds` | `Int` (default 4) | With `tools`: how many rounds may call tools in one request. |
| input  `max_new_tokens` | `Int` (default 512) | Cap on generated tokens; the reply stops there with `stop_reason` `"max_new_tokens"`. |
| input  `enable_thinking` | `Bool?` | Reasoning before the answer, for a model that supports it; absent: the model's default. See [Thinking](#thinking-enable_thinking). |
| input  `seed`, `temperature`, `top_k`, `top_p`, `min_p`, `repetition_penalty`, `min_new_tokens` | — | Accepted, and ignored by the models above: they decode greedily, so the same prompt gives the same reply. The SDK logs one warning when a call sets one. |
| output `text` | `String` | Decoded response (with thinking on, the reasoning and `</think>` first). |
| output `prompt_tokens` / `generated_tokens` | `Int` | Token counts. |
| output `tokens_per_second` | `Double` | Decode speed. |
| output `time_to_first_token` / `total_seconds` | `Double` | Latency breakdown (`prefill_seconds` / `decode_seconds` too). |
| output `stop_reason` | `String` | `"eos"` (the model ended its turn), `"stop_sequence"` or `"max_new_tokens"` (cut off); with tools also `"tool_calls"` and `"max_tool_rounds"`. |
| output `tool_calls`, `final_text`, `thinking` | — | With tools only: the calls the model made, the visible answer, the reasoning. See [Tool calling](#tool-calling). |

From Kotlin, `TheStageLLM.infer(...)` takes the same fields as named
parameters (`sampling: SamplingParams` for the sampling ones) and
returns an `LlmResult` with the outputs above; it also accepts
`stop_sequences: List<String>`, which cuts the decoded text at the
first match (one-shot path only).

## MTP and Thinking

Two optional features depend on the model. `start_model` returns a
status whose `features` say which ones the loaded model has and what
it does by default, so an app can show a switch only where it applies:

```json
"features": {
  "mtp":      {"supported": true, "default": true, "enabled": true},
  "thinking": {"supported": true, "default": true},
  "tools":    {"supported": true, "default": false}
}
```

| Key | Meaning |
|---|---|
| `supported` | The model has the feature. When false, `use_mtp` / `enable_thinking` do nothing, and `tools` throws. |
| `default` | What happens when you don't pass the key. For MTP it can be `false` on a bundle that ships a drafter but does not load it by default — pass `use_mtp: true` to turn it on. |
| `enabled` | MTP only: whether this load runs it (MTP is chosen at load; thinking per request). |

**Kotlin:**

```kotlin
val status = TheStageAI.start_model(
    model_name = "llm",
    engines_path = "TheStageAI/LFM3-1.7B",
)
val thinking = status.features?.get("thinking")
if (thinking?.supported == true) {
    // show a Think switch, initially thinking.default
}
```

`TheStageAI.list_active_models()` reports the same `features`, and a
direct `TheStageLLM` has them as `llm.features`.

**Flutter:**

```dart
final status = await TheStageFlutterSDK.start_model(
  model_name: 'llm',
  engines_path: 'TheStageAI/LFM3-1.7B',
);
final features = status['features'] as Map?;
final mtp = features?['mtp'] as Map?;
final canThink = (features?['thinking'] as Map?)?['supported'] == true;
```

### MTP (`use_mtp`)

MTP (multi-token prediction) speeds up decoding with a small drafter
model that the bundle ships next to the main one: the drafter proposes
several tokens and the main model checks them in one pass. The reply
stays the main model's greedy reply (rarely, two near-equal tokens
resolve the other way). `features.mtp.default` says whether a model
runs MTP when you don't ask; set `use_mtp` in the start config to
choose (it is chosen at load, so switching it means a new
`start_model`):

```kotlin
TheStageAI.start_model(
    model_name = "llm",
    engines_path = "TheStageAI/LFM2.5-1.2B",
    config = mapOf("use_mtp" to false),
)
```

```dart
await TheStageFlutterSDK.start_model(
  model_name: 'llm',
  engines_path: 'TheStageAI/LFM2.5-1.2B',
  config: {'use_mtp': false},
);
```

With MTP off the drafter is not loaded, which saves its memory. A
direct `TheStageLLM` takes the same key through
`pipeline_options = mapOf("use_mtp" to false)`.

### Thinking (`enable_thinking`)

A thinking model can reason before it answers. Pass
`enable_thinking` with each request; when you leave it out, the model
follows its own default (`features.thinking.default`): on for LFM3,
off for Qwen3.5.

```dart
final result = await TheStageFlutterSDK.infer(
  model_name: 'llm',
  input_json: {
    'prompt': 'A train leaves at 9:40 and arrives at 11:05. How long is the trip?',
    'enable_thinking': true,
    'max_new_tokens': 1024,
  },
);
```

The SDK returns the reply as the model writes it, reasoning and
markers included; splitting it is up to your app. Each model family
marks the reasoning its own way:

| Models | Reply with thinking on |
|---|---|
| LFM3, Qwen3.5 | `reasoning</think>answer` (the opening `<think>` is part of the prompt, so the reply starts inside the reasoning) |
| Gemma 4 ([VLM](./vlm.md)) | `<\|channel>thought\nreasoning<channel\|>answer` |

```
The train leaves at 9:40 ... so 1 hour 25 minutes.</think>The trip takes 1 hour 25 minutes.
```

Split at the closing marker to show the reasoning separately, or to
keep only the answer. While a reply streams, everything before the
closing marker is reasoning. Reasoning takes tokens: give thinking
requests a larger `max_new_tokens` (1024 or more). A reply that ends
with `stop_reason` `"max_new_tokens"` before its closing marker was
cut off inside its reasoning and has no answer yet. With thinking off,
the reply has no markers.

This Dart helper splits a reply, complete or still streaming, for
both marker styles:

```dart
/// A reply split into its reasoning and its answer.
class Reply {
  const Reply(this.answer, {this.reasoning, this.open = false});

  /// What follows the reasoning (the whole reply without one).
  final String answer;

  /// The reasoning, trimmed; null when the reply has none.
  final String? reasoning;

  /// No closing marker yet: the reply is still inside its reasoning.
  final bool open;
}

// Closing marker -> the openers that may precede it.
const _markers = {
  '</think>': ['<think>'], // LFM3, Qwen3.5
  '<channel|>': ['<|channel>thought\n', '<|channel>'], // Gemma 4
};

String _stripOpener(String s) {
  final t = s.trimLeft();
  for (final opener in _markers.values.expand((o) => o)) {
    if (t.startsWith(opener)) return t.substring(opener.length);
  }
  return s;
}

/// Splits [text], the reply so far. [thinking]: the request was
/// sent with thinking on.
Reply splitReply(String text, {required bool thinking}) {
  for (final close in _markers.keys) {
    final at = text.indexOf(close);
    if (at >= 0) {
      return Reply(
        text.substring(at + close.length).trim(),
        reasoning: _stripOpener(text.substring(0, at)).trim(),
      );
    }
  }
  final t = text.trimLeft();
  final opened = _markers.values.expand((o) => o).any(t.startsWith);
  if (thinking || opened) {
    return Reply('', reasoning: _stripOpener(text).trim(), open: true);
  }
  return Reply(text);
}
```

Call it on the accumulated text after each streamed `delta`. When
the final chunk arrives and the reply is still `open`, its
`stop_reason` decides: `"max_new_tokens"` means it was cut off inside
its reasoning; `"eos"` means the model answered without reasoning, so
show `reasoning` as the answer.

Keep only the answer when you send a reply back as history (see
[Multi-turn chat](#multi-turn-chat)); the LFM3 and Qwen3.5 templates
drop the reasoning of earlier turns anyway. The [voice agent](./voice_agent.md)
always runs its LLM with thinking off.

## Multi-turn chat

The JSON path keeps a conversation when you pass the history as
`messages` — each earlier user and assistant turn, then the new user
message. The system prompt stays in `system_prompt`. The SDK renders
the whole conversation with the model's chat template, and reuses the
KV cache of the turns it has already seen, so a follow-up costs only
its new tokens.

```dart
final result = await TheStageFlutterSDK.infer(
  model_name: 'llm',
  input_json: {
    'system_prompt': 'You are a helpful assistant.',
    'messages': [
      {'role': 'user', 'content': 'What is the capital of France?'},
      {'role': 'assistant', 'content': 'Paris.'},
      {'role': 'user', 'content': 'And its population?'},
    ],
    'max_new_tokens': 256,
  },
);
```

From Kotlin, pass `prompt = ""` and `messages =
listOf(ChatTurn(ChatTurn.Role.USER, ...), ...)` to `TheStageLLM.infer` /
`infer_stream` (`prompt` is a required parameter; with `messages` the
new user message is the last turn). The conversation
(prompt and reply) must fit the model's context; trim the oldest
turns as it grows.

## Streaming

Token-by-token generation. Each chunk before the terminal sentinel
carries one delta of text; the final chunk has `is_final == true`, the
per-call metrics and the `stop_reason`.

**Kotlin** — `infer_stream` returns a Kotlin `Flow<LlmStreamChunk>`:

```kotlin
llm.infer_stream(
    prompt = "Tell me a story.",
    max_new_tokens = 512
).collect { chunk ->
    if (chunk.is_final) {
        val tps = chunk.tokens_per_second ?: 0.0
        println("\n--- $tps tok/s, ${chunk.stop_reason} ---")
    } else {
        print(chunk.text)
    }
}
```

**Flutter:**

```dart
import 'dart:io';

const streamId = 'llm-reply-1';
final stream = TheStageFlutterSDK.infer_stream(
  model_name: 'llm',
  input_json: {
    'prompt': 'Tell me a story.',
    'max_new_tokens': 512,
  },
  stream_id: streamId,   // needed to stop it early
);

await for (final chunk in stream) {
  if (chunk['is_final'] == true) {
    final tps = chunk['tokens_per_second'] as double? ?? 0;
    print('\n--- $tps tok/s, ${chunk['stop_reason']} ---');
  } else {
    final delta = chunk['delta'] as String?;
    if (delta != null) stdout.write(delta);
  }
}
```

Stop a stream early with `TheStageFlutterSDK.stop_stream(stream_id:
streamId)`, passing the `stream_id` you gave `infer_stream` (each chunk
also carries it as `chunk['stream_id']`). In Kotlin, cancel the
collecting coroutine. The model stops at its next token. See [Streaming](./streaming.md) for the chunk fields.

## Tool calling

A tool is a function in your app that the model may decide to call:
look up an order, read the weather, open the dialer. You describe it
with a name, a description and a JSON Schema for its arguments. The
SDK lists the tools to the model in that model's own format, parses
the call out of the reply as it streams, and hides the call markup:
the text your app shows or speaks never contains it.

| Models | Tools |
|---|---|
| LFM2.5-230M, LFM2.5-350M, LFM2.5-1.2B, LFM3-1.7B | yes |
| Qwen3.5-0.8B, Qwen3.5-2B, Qwen3.5-4B, Qwen3.5-9B | yes |
| [VLM](./vlm.md) models (LFM2.5-VL, Gemma 4) | no — the VLM surface does not read `tools` |

`features.tools.supported` (from `start_model`, or `llm.features` /
`llm.supports_tool_calling` on a direct `TheStageLLM`) says whether
the loaded model calls tools. Passing `tools` to an LLM bundle
without tool support throws `This bundle has no tool_calling spec…`.

Where the tool runs depends on the surface:

- **Kotlin** (`TheStageLLM`): give each `Tool` an `execute`. The SDK
  runs it, feeds the result back and continues the reply on the
  **same stream**, up to `max_tool_rounds` times.
- **Flutter** (and the Kotlin JSON path `TheStageAI.infer_stream`):
  tools are plain JSON and **your app runs them**. The stream ends at
  the call; you run the function, append the result to `messages`
  and call `infer_stream` again.

### Kotlin

```kotlin
import ai.thestage.qlip.TheStageAI
import ai.thestage.qlip.models.llm.LlmStreamEvent
import ai.thestage.qlip.models.llm.TheStageLLM
import ai.thestage.qlip.models.llm.tools.DefaultTools
import ai.thestage.qlip.models.llm.tools.Tool

val dir = TheStageAI.prefetch_model(repo_id = "TheStageAI/Qwen3.5-0.8B")
val llm = TheStageLLM(engines_path = dir)

val order_status = Tool(
    name = "order_status",
    description = "Use when the user asks where an order is. " +
        "Looks up its delivery status by order number.",
    parameters = mapOf(
        "type" to "object",
        "properties" to mapOf(
            "order_id" to mapOf(
                "type" to "string",
                "description" to "Order number, e.g. 4471",
            ),
        ),
        "required" to listOf("order_id"),
    ),
    execute = { call ->
        val id = call.arguments["order_id"] as? String ?: ""
        orders.status_json(id)        // your code: a short JSON string
    },
)

llm.infer_stream(
    prompt = "Where is my order 4471?",
    tools = listOf(order_status) + DefaultTools.live,
    system_prompt = DefaultTools.voice_system_prompt,
    enable_thinking = false,
).collect { event ->
    when (event) {
        is LlmStreamEvent.TextDelta -> bubble.append(event.text)
        is LlmStreamEvent.ToolCallEvent ->
            show_chip("Checking ${event.call.name}…")
        is LlmStreamEvent.Final -> done(event.stop_reason)
        else -> Unit                  // results are for the model
    }
}
```

`infer_stream(…, tools, …)` returns a `Flow<LlmStreamEvent>`:

| Event | What to do |
|---|---|
| `TextDelta(text)` | Append to the bubble; speak it if you have TTS. **The only text to show.** |
| `ThinkingDelta(text)` | Optional "thinking…" indicator; never the answer. |
| `ToolCallEvent(call)` | The model called `call.name` with `call.arguments` (decoded JSON values). Show a chip. |
| `ToolResult(name, content)` | What a tool returned. For the model; do not show or speak it. |
| `ToolRound(assistant_raw)` | A round that called tools ended (its raw reply, markup included). |
| `Final(stop_reason, …)` | The turn is over: `final_text` (every `TextDelta` joined), `tool_calls`, `thinking`, `raw_text` (the last round as generated), token counts and times for all rounds. |

How the loop runs:

- Each call runs on `Dispatchers.IO` with a 15 s timeout
  (`tool_timeout_ms`). A throw or a timeout becomes
  `{"ok":false,"error":"…"}`, which the model reads and answers from.
- The next round continues from the tokens already generated, so it
  prefills only the tool results.
- `max_tool_rounds` (default **4**) caps the rounds that may call
  tools. After the cap, one last round runs with calls ignored (their
  markup still hidden) and `stop_reason` is `"max_tool_rounds"`.
- A call to a name not in `tools` gets the answer
  `{"ok":false,"error":"unknown tool <name>"}`, which the model reads
  (on the Flutter path it ends the stream like any other call).
- Cancelling the collecting coroutine cancels the running tool and
  the generation.
- If the conversation plus the results outgrows the model's context,
  the flow throws an `IllegalStateException`; shorten the history or
  the tool results.

Batch: `llm.infer(prompt = …, tools = …)` runs the same loop to the
end and returns an `LlmResult` with `tool_calls`, `final_text` and
`thinking`; `text` is the last round's raw reply. With an empty
`tools` list, `infer` and `infer_stream` behave exactly as without
tools.

### Flutter

Flutter runs tools in Dart. Send `tools` in `input_json`; when the
model calls one, the stream sends a `tool_call` chunk and ends with a
`final` chunk whose `stop_reason` is `"tool_calls"`. Run the function,
append the call and its result to `messages`, and call `infer_stream`
again with the same `tools`:

```dart
import 'dart:convert';

import 'package:thestage_android_sdk/thestage_android_sdk.dart';

const tools = [
  {
    'name': 'get_weather',
    'description': 'Use when the user asks what the weather is like '
        'now in a city. Returns the temperature in °C and conditions.',
    'parameters': {
      'type': 'object',
      'properties': {
        'city': {'type': 'string', 'description': 'City name, e.g. Paris'},
      },
      'required': ['city'],
    },
  },
];

/// Your tool code. Return a short JSON string.
Future<String> runTool(String name, Map<String, dynamic> args) async {
  if (name == 'get_weather') {
    return jsonEncode({
      'ok': true,
      'city': args['city'],
      'temp_c': 18,
      'conditions': 'partly cloudy',
    });
  }
  return jsonEncode({'ok': false, 'error': 'unknown tool $name'});
}

/// One user question: streams the visible answer into [onText] and
/// runs tools until the model answers.
Future<String> ask(
  String question, {
  void Function(String delta)? onText,
  int maxRounds = 4,
}) async {
  final history = <Map<String, dynamic>>[
    {'role': 'user', 'content': question},
  ];
  final answer = StringBuffer();
  for (var round = 0; round <= maxRounds; round++) {
    final calls = <Map<String, dynamic>>[];
    var stopReason = '';
    var roundText = '';
    final stream = TheStageFlutterSDK.infer_stream(
      model_name: 'llm',
      input_json: {
        'system_prompt': 'You are a helpful assistant. '
            'Use a tool only for live facts the user asked for.',
        'messages': history,
        'tools': tools,
        // The last round must answer: calls are ignored.
        if (round == maxRounds) 'max_tool_rounds': 0,
        'enable_thinking': false,
        'max_new_tokens': 256,
      },
    );
    await for (final chunk in stream) {
      switch (chunk['kind']) {
        case 'text_delta':
          final delta = chunk['delta'] as String? ?? '';
          answer.write(delta);
          onText?.call(delta);
        case 'tool_call':
          calls.add({
            'name': chunk['name'] as String,
            'arguments':
                Map<String, dynamic>.from(chunk['arguments'] as Map),
          });
        case 'final':
          stopReason = chunk['stop_reason'] as String? ?? '';
          roundText = chunk['final_text'] as String? ?? '';
      }
    }
    if (stopReason != 'tool_calls') break;
    history.add({
      'role': 'assistant',
      'content': roundText,
      'tool_calls': calls,
    });
    for (final call in calls) {
      history.add({
        'role': 'tool',
        'name': call['name'],
        'content': await runTool(
          call['name'] as String,
          call['arguments'] as Map<String, dynamic>,
        ),
      });
    }
  }
  return answer.toString();
}

Future<void> main() async {
  await TheStageFlutterSDK.initialize(api_token: 'your-api-token');
  await TheStageFlutterSDK.start_model(
    model_name: 'llm',
    engines_path: 'TheStageAI/Qwen3.5-0.8B',
  );
  final reply = await ask("What's the weather in Paris right now?");
  print(reply); // e.g. "It's 18 °C and partly cloudy in Paris."
}
```

Chunks of a stream with `tools`:

| `chunk['kind']` | Fields | What to do |
|---|---|---|
| `text_delta` | `delta` | Append to the bubble; speak it. **The only text to show.** |
| `thinking_delta` | `delta` | Optional "thinking…" indicator; never the answer. |
| `tool_call` | `name`, `arguments` (`Map`) | Run the tool (after the stream ends, or right away). |
| `tool_result` | `name`, `content` | Only for tools the SDK runs itself; never in a Flutter tool loop. |
| `final` | `stop_reason`, `final_text`, `tool_calls` (`[{name, arguments}]`), `thinking`, `raw_text`, metrics | The request is over. `stop_reason` `"tool_calls"`: run the calls and ask again. `delta` and `raw_text` hold the raw reply with its markup; do not show them. |

Without `tools`, chunks stay `text` + `final` as in
[Streaming](#streaming), and batch `infer` keeps its keys. Batch
`infer` with `tools` returns the same `tool_calls`, `final_text` and
`thinking` keys in its result map.

`messages` with tools:

- `{'role': 'tool', 'content': …}` — a tool result; `name` is
  optional, and a `Map` / `List` content is sent as its JSON.
- `{'role': 'assistant', 'content': …, 'tool_calls': [{name,
  arguments}]}` — the turn that made the calls; `arguments` may be a
  `Map` or a JSON string, and the OpenAI shape `{'type': 'function',
  'function': {…}}` is accepted too. If you append only the tool
  results, the SDK puts back the calls this model made last.
- `tools` entries may also use the OpenAI shape
  `{'type': 'function', 'function': {name, description, parameters}}`.

Keep your own cap on the rounds (`maxRounds` above): every
`infer_stream` call is a new request. `max_tool_rounds: 0` makes the
model answer without calling a tool.

### What the app sees

The model writes a call as markup (for example
`<tool_call>…</tool_call>` on Qwen3.5 and LFM3,
`<|tool_call_start|>[get_weather(city='Paris')]<|tool_call_end|>`
on LFM2.5). The SDK withholds that markup from `text_delta` /
`TextDelta`, so what you receive is only the words the model meant
for the user: often a short filler before the call ("One moment.")
and the answer after the result. Reasoning (`<think>…</think>`) goes to
`thinking_delta`, never to
`text_delta`. `final_text` is all the visible text joined; use it as
the assistant turn's `content` when you keep history.

Small models sometimes drop the call tags. The SDK also reads a call
to one of your tools written without them — `[get_weather(city='Paris')]`
or `get_weather(city='Paris')` on LFM2.5 / LFM3, a bare
`{"name": "get_weather", "arguments": {…}}` (also in a code fence) on
Qwen3.5 — and keeps it out of the text the same way. Without brackets
only the names in `tools` count (case-insensitive), so prose like
"UTC (Tokyo)" stays text. A bracketed call with arguments counts for
any name; one to a name not in `tools` gets the unknown-tool answer,
and a `[note]` stays text. On Qwen3.5 a JSON object that is not a call
(a tool result read back) is left out of the text too.

The tools part of the system prompt also carries a short speaking
hint (a filler sentence, then the call, then a one- or two-sentence
paraphrase of the result). A system prompt that already describes its
own pattern ("Tool pattern (always):", "When you need a tool:", …)
does not get it. On LFM2.5 and LFM3 it also ends with a paragraph on
the call format, which makes those models call more reliably. The
start config's `tool_prompt_style` picks the prompt: `"coached"` (with
that paragraph; the LFM2.5 / LFM3 default), `"template"` (the model's
own chat template and the hint; the Qwen3.5 default) or `"swift"` (the
Apple SDK's text).

### Built-in tools

`DefaultTools` (Kotlin, `ai.thestage.qlip.models.llm.tools`) are
ready-made `Tool`s with `execute`. Use a set as it is, mix it with
your own tools, or pick single tools (`DefaultTools.get_weather`):

| Set | Tools |
|---|---|
| `DefaultTools.live` | `get_weather`, `get_local_time`, `web_search` |
| `DefaultTools.web` | `live` + `wikipedia_summary`, `calculate` |
| `DefaultTools.phone` | `open_url`, `dial_phone`, `open_maps`, `compose_sms`, `compose_email`, `copy_to_clipboard`, `get_battery` |
| `DefaultTools.voice` / `DefaultTools.all` | `web` + `phone` |
| `DefaultTools.web_mock` | Canned answers with no network, for demos and tests: `web` plus `send_message` and `compose_email` |
| `DefaultTools.web_mock_live` | Canned `live` |

`DefaultTools.voice_system_prompt` is a system prompt for a short
spoken assistant that uses tools only for live facts.

What they do and where data goes:

| Tool | Runs | Sends |
|---|---|---|
| `get_weather`, `get_local_time` | [Open-Meteo](https://open-meteo.com) geocoding and forecast (no API key) | The city name |
| `web_search` | DuckDuckGo (the results page, then the Instant Answer API), then Wikipedia search | The query |
| `wikipedia_summary` | Wikipedia REST summary (en.wikipedia.org) | The title |
| `calculate` | On device | Nothing |
| phone tools | On device: they open the browser, dialer, maps, SMS or e-mail composer for the user to confirm (the dialer opens; it never places a call), copy to the clipboard, read the battery | Nothing |

- The web tools need network access; the requests carry the user
  agent `TheStageSDK-DefaultTools/1.0 (+https://thestage.ai;
  voice-agent tools)`, except the DuckDuckGo results page, which gets
  a browser's. Their answers are short plain
  text; a failure is a sentence the model can say ("Weather lookup
  failed."), never a throw.
- The phone tools need `TheStageAI.registerContext(context)` and
  return `{"ok":true,…}` or `{"ok":false,"error":"…"}`.
- The SDK never logs tool arguments, results or queries. The text
  the model sends to a tool — and so to the service behind it — comes
  from the conversation; tell your users when a tool sends their
  words off the device, or use only on-device tools.
- From Flutter the built-in tools are not callable as Dart functions;
  run your own Dart code in the tool loop. The
  [voice agent](./voice_agent.md) uses the built-in sets for you.

### Reliable calls from a small model

The supported models are small. They call tools well when the job is
narrow:

- **Few tools.** Give each request only the tools it can need — two
  or three, not twenty. Every tool costs prompt tokens and is one
  more wrong choice.
- **Say when, not just what.** The model chooses by the
  `description`: "Use when the user asks what the weather is like
  now in a city" works better than "Weather API".
- **Simple arguments.** Few parameters, strings or numbers, each
  with a `description` and an example; mark the needed ones
  `required`.
- **Short results.** Return a short JSON object or sentence; the
  model reads it verbatim and a long payload fills the context.
- **A system prompt that says when not to call.** Greetings and
  chit-chat should get a direct answer; `voice_system_prompt` shows
  one way to say it.
- **Thinking off** for chat (`enable_thinking = false`): the reply
  starts sooner and the call comes first.
- **Check the call in your app.** Validate the arguments before you
  act, and keep phone-like actions behind the user's confirmation.

### Troubleshooting tools

| Symptom | Cause | Fix |
|---|---|---|
| Passing `tools` throws `This bundle has no tool_calling spec…` | The bundle has no tool format. | Use a model from the table above; check `features.tools.supported`. |
| The model never calls the tool | The description does not say when to use it, or too many tools. | Rewrite the `description` as "Use when the user asks …"; pass fewer tools. |
| The model calls a tool for "thanks" or "hello" | No rule for when not to call. | Say it in the system prompt (see `voice_system_prompt`). |
| Wrong or missing arguments | Vague parameter names or no examples. | Add a `description` with an example to each parameter; mark it `required`. |
| Flutter: the stream ends with no answer | `stop_reason` is `"tool_calls"`: the model is waiting for the result. | Run the call, append the `tool` message, call `infer_stream` again. |
| Flutter: markup shows in the bubble | Rendering the `final` chunk's `delta` or `raw_text`. | Render only `text_delta` (or `final_text`). |
| `stop_reason` `"max_tool_rounds"` | The model kept calling tools. | Check the tool results answer the question; raise `max_tool_rounds` only if more steps are real. |
| A web tool answers "Weather lookup failed." / "No web results…" | No network, or the service had no answer. | Check connectivity; the model can still say the sentence. |
| `IllegalStateException` "no longer fits the model's context" | History plus tool results is too long. | Trim old turns; return shorter results. |
| A phone tool returns `{"ok":false,…}` | No context registered, or no app handles the action. | Call `TheStageAI.registerContext(context)`; check the device has the app. |

## Singleton API (`TheStageAI`)

Use this when you want lifecycle (`stop_model`), JSON dispatch
(`infer(model_name, input_json)`), auto-download, or are driving the
SDK from Flutter. Both flows share the same on-disk cache. `TheStageAI`
is a Kotlin `object` (singleton); its methods are `suspend`.

```kotlin
TheStageAI.start_model(
    model_name = "llm",
    engines_path = "TheStageAI/LFM2.5-1.2B"
)

val json = TheStageAI.infer(
    model_name = "llm",
    input_json = mapOf(
        "prompt" to "What is 2+2?",
        "system_prompt" to "You are a helpful assistant.", // optional
        "max_new_tokens" to 256,                            // optional
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

The Flutter `TheStageFlutterSDK.infer` / `infer_stream` calls hit this
exact JSON path, so the response keys above apply unchanged on Dart.

## Full Constructor

```kotlin
val llm = TheStageLLM(
    engines_path = dir,                    // local (prefetched) dir
    device = "npu",                        // the bundle places its engines
    chat_template_override = null,         // null = use the bundle's
    system_prompt_override = null,         // null = use the bundle's
    eos_token_id_override = null,          // null = use the bundle's
    pipeline_options = mapOf("use_mtp" to true), // null = defaults
)
```

> `device` is accepted so the Kotlin and Flutter/JSON call sites match,
> but backend routing (framework + device) is authoritative in the
> bundle, so an override here is a no-op by design. The context size
> likewise comes from the bundle.

The direct constructor loads from a **local** directory only — it does
not download. Use `TheStageAI.prefetch_model(...)` (or `start_model`)
to fetch the bundle first. `TheStageAI.initialize(...)` must have
succeeded before either call.

## Load Progress

The direct `TheStageLLM` constructor loads from a local dir and emits
no progress. Download / extract / load progress is reported through the
singleton and Flutter entry points via an optional `on_load_progress`
handler. `phase` is the signal; `fraction` is non-null only while
downloading, where it runs `0.0 .. 1.0`:

```kotlin
TheStageAI.start_model(
    model_name = "llm",
    engines_path = "TheStageAI/LFM2.5-1.2B",
    on_load_progress = { p ->
        // p.phase ∈ { DOWNLOADING, WAITING_FOR_WIFI,
        //            WAITING_FOR_CONFIRMATION, EXTRACTING,
        //            LOADING, READY }
        // p.fraction: Double? - 0.0 .. 1.0 while DOWNLOADING
        //   (and 1.0 on READY); null on every other phase,
        //   which have no measurable progress
        // p.downloaded_bytes / p.total_bytes: Long?, set during
        //   DOWNLOADING when the server declared a size
        val pct = p.fraction?.let { " ${(it * 100).toInt()}%" } ?: ""
        println("[${p.model}] ${p.phase}$pct")
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
  // phase: downloading | waiting_for_wifi |
  //        waiting_for_confirmation | extracting | loading | ready
  final phase    = event['phase']    as String?;
  // Present only while downloading. Null => drive an
  // indeterminate indicator; do NOT fall back to 0.
  final fraction = event['progress'] as num?;
  final pct = fraction == null
      ? ''
      : ' ${(fraction * 100).toStringAsFixed(0)}%';
  print('[llm] $phase$pct');
});

await TheStageFlutterSDK.start_model(
  model_name: 'llm',
  engines_path: 'TheStageAI/LFM2.5-1.2B',
);
```

## Prefetch Engines

If you'd rather download bundles ahead of time (e.g. on a "Download
models" screen) so a later construction is a pure local load, use
`prefetch_model`:

```kotlin
val engines_dir = TheStageAI.prefetch_model(
    repo_id = "TheStageAI/LFM2.5-1.2B"
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

## Example apps

- `examples/engine_bench` — the **LLM** tab streams a reply from each
  model with `infer_stream`, shows the MTP switch from the model's
  `features`, and measures TTFT and decode tok/s.
- `examples/tutor_small_llms` — batch `infer` with `messages` and
  thinking off: a small LLM turns a receipt, a chat or an SMS into
  structured data; guide 5 runs the Flutter tool loop and scores
  the model's tool choice and arguments.
- `examples/voice_agent` — the LLM inside a full voice loop (mic →
  VAD → STT → LLM → streaming TTS), with thinking off.

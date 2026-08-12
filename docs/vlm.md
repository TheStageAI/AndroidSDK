# VLM (Vision-Language Model)

On-device image + text → text. `TheStageVLM` (LFM2.5-VL) runs the vision
encoder and the language decoder entirely on-device — hand it an image
and a prompt, get back a text answer. Batch and token-by-token streaming
share the same response shape as the LLM path.

- **`model_name`:** `lfm2-vl`
- **HF engines:** `TheStageAI/LFM2.5-VL-450M`

## Basic Usage

**Kotlin** — via the singleton:

```kotlin
import ai.thestage.qlip.TheStageAI

TheStageAI.registerContext(context)
TheStageAI.initialize(api_token = "your-api-token")

TheStageAI.start_model(
    model_name = "lfm2-vl",
    engines_path = "TheStageAI/LFM2.5-VL-450M",
)

val result = TheStageAI.infer(
    model_name = "lfm2-vl",
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
  model_name: 'lfm2-vl',
  engines_path: 'TheStageAI/LFM2.5-VL-450M',
);

final result = await TheStageFlutterSDK.infer(
  model_name: 'lfm2-vl',
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
| `image` | `String` | required | File path to the input image. |
| `prompt` | `String` | required | Question / instruction about the image. |
| `preset` | `String` | `"medium"` | Image tiling: `"medium"` (single tile) or `"high"` (grid + thumbnail, more detail at higher cost). |
| `system_prompt` | `String?` | — | Optional ChatML system message. |
| `max_new_tokens` | `Int` | 512 | Cap on generated tokens. |
| `seed`, `temperature`, `top_k`, `min_p`, `repetition_penalty` | — | — | Per-call sampling overrides — omit to keep the bundle's preset. |
| output `text` | `String` | — | The generated answer. |

The result also carries `prompt_tokens` / `image_tokens` / token counts
and timing (`prompt_ms`, …) for diagnostics.

## Streaming

`infer_stream` streams text deltas exactly like the LLM path — each
chunk before the terminal one carries a `text` delta; the final chunk
has `is_final == true`.

```dart
final stream = TheStageFlutterSDK.infer_stream(
  model_name: 'lfm2-vl',
  input_json: {
    'image': '/path/to/photo.jpg',
    'prompt': 'Describe this scene in detail.',
    'max_new_tokens': 256,
  },
);

await for (final chunk in stream) {
  if (chunk['is_final'] == true) break;
  stdout.write(chunk['text']);
}
```

See [Streaming](./streaming.md) for the shared chunk contract and
[Model Management](./model_management.md) for loading the VLM's vision
encoder + decoder components independently.

# Embeddings (EmbeddingGemma)

On-device embeddings for search, clustering and similarity. Two
models share model type `embedding-gemma`:

| Repo | Inputs | Vector |
|---|---|---|
| `TheStageAI/embeddinggemma-300m` | text | 768 floats |
| `TheStageAI/embeddinggemma-2` | text, image, audio, video | 768 floats, or a shorter Matryoshka size |

Both run on the Snapdragon NPU. Every vector is L2-normalized, so the
cosine similarity of two vectors is their dot product.

## Basic Usage

**Kotlin**:

```kotlin
import ai.thestage.qlip.TheStageAI

TheStageAI.registerContext(context)
TheStageAI.initialize(api_token = "your-api-token")

TheStageAI.start_model(
    model_name = "embed",
    model_type = "embedding-gemma",
    engines_path = "TheStageAI/embeddinggemma-2",
)

val out = TheStageAI.infer(
    model_name = "embed",
    input_json = mapOf(
        "text" to "How do I reset my password?",
        "task" to "query",
    ),
)[0]
val vector = out["embedding"] as List<Double>
```

**Flutter**:

```dart
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');
await TheStageFlutterSDK.start_model(
  model_name: 'embed',
  model_type: 'embedding-gemma',
  engines_path: 'TheStageAI/embeddinggemma-2',
);

final out = (await TheStageFlutterSDK.infer(
  model_name: 'embed',
  input_json: {
    'image_path': '/path/to/photo.jpg',
    'task': 'document',
  },
)).first;
final vector = (out['embedding'] as List).cast<double>();
print(out['embedding_space_id']);
```

## Inputs

| Key | Type | Default | Notes |
|---|---|---|---|
| `text` | String | none | Text to embed |
| `task` | String | none | A task prompt name, EmbeddingGemma 2 only |
| `dimension` | Int | full size | A Matryoshka size, EmbeddingGemma 2 only |
| `image_path` | String | none | An image file, EmbeddingGemma 2 only |
| `audio_path` | String | none | An audio file, EmbeddingGemma 2 only |
| `video_path` | String | none | A video file, EmbeddingGemma 2 only |
| `max_frames` | Int | the model's | Video frames at most; see [Video](#video) |

Give `text`, a media path, or both. Paths are files the app can read.
On EmbeddingGemma-300m, `task` or a `dimension` other than 768 fails
the call.

## Outputs

The response is a single-element list:

| Key | Type | Notes |
|---|---|---|
| `embedding` | `List<Double>` | The unit vector |
| `embedding_b64` | String | The same vector: base64 of float32 little-endian bytes |
| `embedding_dtype` | String | `"float32"` |
| `embedding_dim` | Int | Length of the vector |
| `dimension` | Int | Length of the vector; EmbeddingGemma 2 only |
| `embedding_space_id` | String | Vectors compare only when this matches; EmbeddingGemma 2 only |
| `token_count` | Int | Tokens of the input sequence; EmbeddingGemma 2 only |
| `truncated` | Bool | Input was dropped; EmbeddingGemma 2 only |

`embedding_space_id` names the model and ends with `@<dimension>`.
Store it next to each vector and compare only vectors with the same
id: two models, or two Matryoshka sizes of one model, give vectors
that are not comparable.

## Task prompts

EmbeddingGemma 2 embeds best with the prompt of the task: `task`
puts that prompt before the input. Use `query` for a search query
and `document` for the texts it searches; `STS` is for sentence
similarity. The bundle carries more names, and an unknown name fails
the call with the list of valid ones.

Embed queries and documents with their own tasks, but compare them in
one space: the task does not change `embedding_space_id`.

EmbeddingGemma-300m takes no `task`; put any prefix you want in
`text` itself.

## Matryoshka dimensions

`dimension` on EmbeddingGemma 2 keeps the first values of the vector
and normalizes them again: **768** (full), **512**, **256** or
**128**. A smaller vector is cheaper to store and search. `0` or
`768` returns the full vector; any other size fails the call with
the list of valid ones.

## Long text

One pass reads up to **2048 tokens**, prompt included.

- **EmbeddingGemma 2** cuts a longer text at that window: the rest is
  not embedded, and the result has `truncated: true`. Split long
  documents yourself and embed each piece.
- **EmbeddingGemma-300m** reads a longer text in 2048-token pieces
  and returns their average, weighted by token count and normalized.

A text plus media input that passes the window fails the call; it
is never cut.

## Media inputs

EmbeddingGemma 2 embeds images, audio and video, alone or together
with text. Parts are embedded as **one** input, in this order: the
task prompt, `text`, the image, the audio, the video. An image with
its caption gives one vector for both; for separate vectors, make
separate calls.

### Image

Any format Android's `BitmapFactory` decodes. A file that cannot be
decoded fails the call.

### Audio

Any format Android's `MediaCodec` decodes (WAV, MP3, AAC, FLAC, ...):
the first audio track, channels mixed to mono and resampled for the
model. Audio past **30 s** is dropped and the result has
`truncated: true`.

### Video

The first video track, sampled at the model's frame rate, up to
**14 frames** by default. When the video has more sampled frames
than that, frames are taken evenly across the whole video.
`max_frames` lowers the limit; a larger value is capped to 14.

## Supported devices

Snapdragon 8 Gen 2 (SM8550), 8 Gen 3 (SM8650), 8 Elite (SM8750) and
8 Elite Gen 5 (SM8850). Both models publish one NPU bundle for these
chips and no CPU bundle, so `device: "cpu"` fails, and so does a
start on another chip. Use the
[availability check](./model_management.md#availability) before
offering the feature.

## Agent checklist

- Model type `embedding-gemma`; repos `TheStageAI/embeddinggemma-300m`
  (text) and `TheStageAI/embeddinggemma-2` (text, image, audio,
  video).
- Read `embedding` (doubles) or decode `embedding_b64` (float32,
  little-endian). Vectors are unit length: cosine = dot product.
- EmbeddingGemma 2: `task` (`query` / `document` / `STS` / ...) and
  `dimension` (768, 512, 256, 128); compare only vectors with equal
  `embedding_space_id`.
- EmbeddingGemma 2 cuts text past 2048 tokens (`truncated`);
  EmbeddingGemma-300m averages 2048-token pieces.
- Media are file paths: `image_path`, `audio_path`, `video_path`
  (+ `max_frames`).

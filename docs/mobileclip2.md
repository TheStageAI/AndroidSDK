# Image Embeddings (MobileCLIP2)

On-device image embeddings for photo search, deduplication and
grouping. The model is the image encoder of **MobileCLIP2-S0**,
shipped as `TheStageAI/MobileCLIP2-S0-image-encoder` and addressed by
model type `mobile-clip-image`. It turns one image into a
**512-float, L2-normalized** vector, so the cosine similarity of two
images is the dot product of their vectors.

The SDK ships the image encoder only: it does not embed text.

## Basic Usage

**Kotlin**:

```kotlin
import ai.thestage.qlip.TheStageAI

TheStageAI.registerContext(context)
TheStageAI.initialize(api_token = "your-api-token")

TheStageAI.start_model(
    model_name = "clip",
    model_type = "mobile-clip-image",
    engines_path = "TheStageAI/MobileCLIP2-S0-image-encoder",
)

val out = TheStageAI.infer(
    model_name = "clip",
    input_json = mapOf("image" to "/path/to/photo.jpg"),
)
val vector = out.firstOrNull()?.get("embedding") as? List<Double>
```

**Flutter**:

```dart
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');
await TheStageFlutterSDK.start_model(
  model_name: 'clip',
  model_type: 'mobile-clip-image',
  engines_path: 'TheStageAI/MobileCLIP2-S0-image-encoder',
);

final out = await TheStageFlutterSDK.infer(
  model_name: 'clip',
  input_json: {'image': '/path/to/photo.jpg'},
);
final vector = out.isEmpty
    ? null
    : (out.first['embedding'] as List).cast<double>();
```

## Inputs

| Key | Type | Default | Notes |
|---|---|---|---|
| `image` | String | — | Required. Path to an image file the app can read |

Any format Android's `BitmapFactory` decodes. The encoder sees the
**centered square** of the image, scaled to its input size: crop
first if the subject is off-center. EXIF orientation is not applied,
so save photos upright.

## Outputs

| Key | Type | Notes |
|---|---|---|
| `embedding` | `List<Double>` | 512 floats, unit length |
| `modality` | String | `"image"` |
| `preprocess_ms` | Double | Crop and scale time of this call |
| `inference_ms` | Double | Encoder time of this call |
| `total_ms` | Double | `preprocess_ms + inference_ms` |

The response is a single-element list, or an **empty list** when the
file is missing or cannot be decoded.

## NPU and CPU bundles

The model publishes two bundles:

- an **NPU bundle** for Snapdragon 8 Gen 2 (SM8550), 8 Gen 3
  (SM8650), 8 Elite (SM8750) and 8 Elite Gen 5 (SM8850);
- a **CPU bundle** for every other phone, and as the fallback.

With `device` unset, the SDK starts the NPU bundle on those chips and
the CPU bundle on every other phone. If the NPU bundle does not open
on a supported chip, the start falls back to the CPU bundle on its
own. `device: "npu"` or `"cpu"` requires one bundle and fails instead
of falling back. Both bundles return vectors in the same format. See
[Model Management → Choosing the device](./model_management.md#choosing-the-device).

## Agent checklist

- Model type `mobile-clip-image`; repo
  `TheStageAI/MobileCLIP2-S0-image-encoder`.
- Input is `image`: a file path, from Kotlin and Flutter alike.
- Output `embedding` is 512 doubles, unit length: cosine = dot
  product. An empty response means the image was not read.
- Image only: no text embeddings.
- Leave `device` unset to get the NPU on supported chips and the CPU
  bundle everywhere else.

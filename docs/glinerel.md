# Entities, Personal Data and Relations (GLiNEREL)

On-device extraction of named entities, personal data and the
relations between them, with **labels you choose at call time**:
"person", "email", "works for" — any wording. The model is
**SauerkrautLM-GLiNEREL-72m** (English, German, French, Italian,
Spanish), shipped as `TheStageAI/GLiNEREL-72m` and addressed by model
type `glinerel`. It runs on the Snapdragon NPU; a short text takes a
few tens of milliseconds.

## Basic Usage

**Kotlin**:

```kotlin
import ai.thestage.qlip.TheStageAI

TheStageAI.registerContext(context)
TheStageAI.initialize(api_token = "your-api-token")

TheStageAI.start_model(
    model_name = "glinerel",
    model_type = "glinerel",
    engines_path = "TheStageAI/GLiNEREL-72m",
)

val out = TheStageAI.infer(
    model_name = "glinerel",
    input_json = mapOf(
        "text" to "Marie Curie was born in Warsaw.",
        "entities" to listOf("person", "location"),
        "relations" to listOf("born in"),
    ),
)[0]
val entities = out["entities"] as List<Map<String, Any>>
val relations = out["relations"] as List<Map<String, Any>>
```

**Flutter**:

```dart
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');
await TheStageFlutterSDK.start_model(
  model_name: 'glinerel',
  model_type: 'glinerel',
  engines_path: 'TheStageAI/GLiNEREL-72m',
);

final out = (await TheStageFlutterSDK.infer(
  model_name: 'glinerel',
  input_json: {
    'text': 'Call Laura Bianchi at +39 347 555 0192.',
    'entities': ['first name', 'last name', 'phone number'],
    'redact': true,
  },
)).first;
print(out['redacted_text']);   // Call [FIRST_NAME] [LAST_NAME] at [PHONE_NUMBER].
```

## Inputs

| Key | Type | Default | Notes |
|---|---|---|---|
| `text` | String | — | Required |
| `entities` | labels | none | `["person", ...]`, `[{"label": "person", "threshold": 0.6}]` or `{"person": 0.6}` |
| `relations` | labels | none | Relation labels, the same forms |
| `entity_threshold` | Double | `0.5` | For entity labels without their own threshold |
| `relation_threshold` | Double | `0.25` | For relation labels without their own threshold |
| `trim_punctuation` | Bool | `true` | Drop punctuation glued to the edges of a span |
| `merge_mentions` | Bool | `false` | Keep one relation per pair of entity surfaces |
| `redact` | Bool | `false` | Also return `redacted_text` |
| `placeholder` | String | `[{label}]` | Replacement for a redacted entity; `{label}` becomes the label in upper case with `_` for spaces |

Give at least one entity or relation label. One call holds at most
**32 label markers**: each entity label takes one, each relation
label two (`entities + 2 × relations ≤ 32`).

## Outputs

| Key | Type | Notes |
|---|---|---|
| `entities` | `[{label, text, start, end, score}]` | By position in the text |
| `relations` | `[{label, head: {text, start, end}, tail: {text, start, end}, score}]` | By score, best first |
| `redacted_text` | String | With `redact` only |

`start` / `end` are offsets into `text` in UTF-16 units — the units of
Kotlin and Dart strings — with `end` exclusive, so
`text.substring(start, end)` is the span. Scores are probabilities in
`[0, 1]`. The response is a single-element list.

## Long texts

One pass reads up to 512 tokens. A longer text is read in pieces cut
at word boundaries (after a sentence end where possible): entities
come from the whole text, relations from within one piece.

## Agent checklist

- Model type `glinerel`; common handle `glinerel`; repo
  `TheStageAI/GLiNEREL-72m`.
- Labels are free text; short noun phrases work best ("person",
  "email address", "works for").
- `entities + 2 × relations ≤ 32` per call; split a larger schema
  into several calls on the same text.
- Offsets are UTF-16; use them with `substring`, not byte offsets.

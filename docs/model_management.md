# Model Management

Cross-cutting helpers for working with model bundles around the core
`start_model` / `infer` / `stop_model` flow: probe availability before
downloading, pre-fetch engines, load or drop individual components of a
multi-part model, resolve an engine shipped inside your APK, and read
process memory.

## Availability

`check_model_availability` tells you whether a bundle is usable on this
device **before** you commit to loading it — no `initialize`, no token,
no download (a HEAD request for a HuggingFace repo, a file stat for a
local path). Use it to pick a model or drive UI ahead of the heavier
`start_model`.

**Kotlin:**

```kotlin
import ai.thestage.qlip.TheStageAI

val result = TheStageAI.check_model_availability(
    model_path = "TheStageAI/thewhisper-large-v3-turbo",
    revision = "main",
)
when (result.availability) {
    ModelAvailability.REMOTE -> { /* publishable — will download */ }
    ModelAvailability.LOCAL  -> { /* already on disk */ }
    ModelAvailability.NONE   -> { /* result.reason says why */ }
    ModelAvailability.UNKNOWN -> { /* couldn't determine */ }
}
```

**Flutter:**

```dart
final result = await TheStageFlutterSDK.check_model_availability(
  model_path: 'TheStageAI/thewhisper-large-v3-turbo',
);
if (result.availability == ModelAvailability.remote ||
    result.availability == ModelAvailability.local) {
  // safe to start_model
}
```

| Value | Meaning |
|---|---|
| `remote` | A published bundle exists for this device (HF) and will download on `start_model`. |
| `local` | The given path is a bundle already present on disk. |
| `none` | Nothing available — inspect `result.reason` (`repo_not_found`, `variant_unavailable`, `local_missing`, `network_unreachable`). |
| `unknown` | Could not determine (e.g. a transport failure during the probe). |

`model_path` is an HF repo id or a local bundle path; `revision`
defaults to `main`.

For a Play-delivered model, `model_path` may also be an
`aipack://<packName>` source (see below). Those results carry the
extra reason `aipack_pack` — reported on an **available** result
(`local` when the pack is on the device, `remote` when it is still
fetchable), not on `none`. `compute` is always null for an AI pack.
See [ai_packs.md](./ai_packs.md) for the full behavior.

## Engines source: Google Play AI packs

Alongside an HF repo id and a local path, `engines_path` accepts an
`aipack://<packName>` source: a model bundle your app ships inside its
AAB as a Google Play **AI pack** (Play for On-device AI / Play Asset
Delivery). Play hosts it for free, delivers only the per-SoC variant a
device needs, pre-downloads it after install (fast-follow) or on first
use (on-demand), and delta-patches it across app updates. Everything
about the `start_model` / `infer` flow is unchanged — only the
`engines_path` string differs, and a few `aipack_*` config keys
(release tag, keep-pack, HF fallback) tune delivery.

```dart
await TheStageFlutterSDK.start_model(
  model_name: 'stt',
  engines_path: 'aipack://thestageai_models_whisper',
  config: {'aipack_release_tag': 'whisper-0.2.3'},
);
```

The AI pack itself is a Gradle module in your app project — building
it is a one-time app-side setup. See
[ai_packs.md](./ai_packs.md) for the full integration guide (pack
modules, device targeting, delivery modes, availability, testing).

## Prefetch

`prefetch_model` downloads and extracts a bundle **without** loading it
into memory, returning the local engines directory. Hand that path to
`start_model` (or a direct model constructor) later to skip the download
phase. Progress is reported on `on_progress` with the repo id as the
`model_name`. See the per-model guides ([llm.md](./llm.md),
[whisper.md](./whisper.md), [tts.md](./tts.md)) for usage in context.

## Components

A multi-part bundle (for example a VLM's vision encoder + decoder)
exposes its parts as **components**. You can list them, and load or drop
individual ones to trade memory against latency — e.g. unload a vision
encoder while a long text-only conversation runs, then load it back when
an image arrives.

**Kotlin:**

```kotlin
val parts = TheStageAI.list_components(model_name = "vlm")
// [{ "id": "encoder", "state": "loaded" },
//  { "id": "decoder", "state": "loaded" }]

TheStageAI.unload_components(
    model_name = "vlm", component_ids = listOf("encoder"),
)
// ... later, before sending an image:
TheStageAI.load_components(
    model_name = "vlm", component_ids = listOf("encoder"),
)
```

**Flutter:**

```dart
final parts = await TheStageFlutterSDK.list_components(
  model_name: 'vlm',
);
await TheStageFlutterSDK.unload_components(
  model_name: 'vlm', component_ids: ['encoder'],
);
await TheStageFlutterSDK.load_components(
  model_name: 'vlm', component_ids: ['encoder'],
);
```

Each of the three returns the current component list as
`[{ "id": String, "state": "loaded" | "unloaded" }, …]`. `load` /
`unload` are idempotent — a component already in the requested state is
left as-is.

## Bundled Engines

`get_bundled_engine_path` resolves the on-disk path of an engine file
you ship **inside the APK** (packaged under the app's assets/jniLibs),
so you can pass it as a local `engines_path` and skip any download.
Returns `null` if the file isn't bundled.

```dart
final path = await TheStageFlutterSDK.get_bundled_engine_path(
  'silero-vad',
);
if (path != null) {
  await TheStageFlutterSDK.start_model(
    model_name: 'vad', engines_path: path,
  );
}
```

## Process Memory

`memory_footprint` reports how the OS accounts this process's memory —
useful for on-device memory HUDs and for deciding when to unload
components.

```dart
final mem = await TheStageFlutterSDK.memory_footprint();
if (mem != null) {
  final pss = mem['footprint_mb'];   // total PSS in MB
  final rss = mem['resident_mb'];    // RSS in MB (secondary)
}
```

`footprint_mb` is total PSS in MB — the number the low-memory killer
tracks, and the one to watch. `resident_mb` (RSS) is a smaller secondary
diagnostic. Returns `null` if the platform couldn't read the footprint.

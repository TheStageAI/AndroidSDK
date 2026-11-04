# Model Management

Cross-cutting helpers for working with model bundles around the core
`start_model` / `infer` / `stop_model` flow: choose which bundle a
device gets, probe availability before downloading, pre-fetch engines,
see what is installed and take updates, reclaim space, load or drop
individual components of a multi-part model, resolve an engine shipped
inside your APK, and read process memory.

## Choosing the device

A model can publish two kinds of bundle: an **NPU** bundle compiled
for the Snapdragon NPU (for some models one bundle serves every
supported chip, for others there is one per chip), and a **portable**
bundle that runs on the CPU. `device` on `start_model` and
`prefetch_model` chooses between them:

| `device` | What loads |
|---|---|
| unset (default) | The best bundle for this phone: the NPU bundle if the model publishes one for its chip, otherwise the portable one. |
| `"npu"` | The NPU bundle. **Fails** if the model publishes none for this chip. |
| `"cpu"` | The portable bundle. **Fails** if the model publishes none. |
| `"gpu"` | Refused: the GPU is not supported. |

Leave it unset unless a requirement is real. An unmet `"npu"` or
`"cpu"` fails with a message naming the chip, what the repo publishes
and how to stop asking, rather than quietly loading the other kind.
That is the point of passing it: an app that must not run a model on
the CPU says so, and learns at load time instead of from a benchmark.

`device` chooses the **bundle**. Where each engine inside it runs is
part of the bundle — a speech model's mel front-end stays on the CPU
whatever you pass — and `devices` overrides that per module.

```dart
// Best available: what almost every app wants.
await TheStageFlutterSDK.start_model(
  model_name: 'llm',
  engines_path: 'TheStageAI/LFM2.5-350M',
);

// Required: fail rather than run on the CPU.
await TheStageFlutterSDK.start_model(
  model_name: 'llm',
  engines_path: 'TheStageAI/LFM2.5-350M',
  device: 'npu',
);
```

The language models (LLM and VLM) publish only NPU bundles, for the
chips listed under [Supported Devices](./README.md#supported-devices).

## Availability

`check_model_availability` tells you whether a bundle is usable on this
device **before** you commit to loading it — no download (a HEAD
request for a HuggingFace repo, a file stat for a local path). Use it
to pick a model or drive UI ahead of the heavier `start_model`.

**Before `initialize`** it answers from local state only: a bundle
already staged for this device returns `LOCAL`, as does a local path
or a Play pack. That covers the usual launch question — "do I need to
download anything?" — with no token and no network. A repo that is
**not** yet on disk needs a remote probe, which requires
`initialize`; until then it reports `unknown` with reason
`not_initialized` rather than guessing.

A repo whose bundle is already cached returns `LOCAL` with the staged
directory as `source` and its on-disk size, so you can tell "ready to
load" from "needs 594 MB" without tracking downloads yourself.

**Kotlin:**

```kotlin
import ai.thestage.qlip.ModelAvailability
import ai.thestage.qlip.TheStageAI

val result = TheStageAI.check_model_availability(
    model_path = "TheStageAI/thewhisper-large-v3-turbo",
    // No `revision`: the SDK resolves this repo's pinned
    // commit. Passing a branch name here would override the
    // pin and is not what you want.
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

`model_path` is an HF repo id or a local bundle path.

`revision` defaults to `""`, which means **resolve this repo's
pinned commit** from the SDK's built-in table — not `main`, and not
any branch. Every model the SDK ships is pinned to an exact commit,
so leaving it blank is the correct and expected usage. Passing a
value overrides the pin; passing a mutable ref such as a branch name
gives up the guarantee that the bytes cannot change under you. A
blank revision for a repo with no pin is an error
(`UnpinnedRepoError`) rather than a silent fallback.

For a Play-delivered model, `model_path` may also be an
`aipack://<packName>` source (see below). Those results carry the
extra reason `aipack_pack` — reported on an **available** result
(`local` when the pack is on the device, `remote` when it is still
fetchable), not on `none`. `compute` is always null for an AI pack.
See [ai_packs.md](./ai_packs.md) for the full behavior.

## Private Hugging Face repos

Public models download without a token. For a private or gated repo,
pass a Hugging Face access token once at init:

```dart
await TheStageFlutterSDK.initialize(
  api_token: sdkToken,
  hf_token: hfToken, // optional
);
```

The SDK keeps the token in memory only and sends it as
`Authorization: Bearer` to `huggingface.co` alone. It strips the token
on the CDN redirects that serve the bundle bytes, never sends it to
TheStage backend, and never logs it. A later `initialize` without
`hf_token` keeps the token already set. When the Hub answers 401/403,
the load fails with an access-denied error: the repo is private or
gated and no token was passed, or the token lacks access (for a gated
repo, accept its terms on the Hub with the same account).

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

Pass the same `device` you will pass to `start_model` (or leave both
unset), so the prefetch installs the bundle the load will look for.
A model that is already installed is left as it is; pass
`replace_existing: true` to take an update (see below).

## Installed models and updates

**A load never replaces what is installed.** `start_model` serves the
bundle on the device, with no network, even when this build of your
app pins a newer one: replacing it would spend the user's data and
stall the session they are in, for a change they did not ask for.
Your app decides when to update.

| Call | What it does |
|---|---|
| `installed_models()` | Every model staged on this device, largest first, with its repo, commit and size on disk. Local: no network. |
| `available_updates()` | Every installed model for which this build pins a newer bundle, each with its `repository`. Reports only; nothing downloads. |
| `update_available(model_type:, repository:)` | The same question for one model; null when it is current or not installed. |
| `prefetch_model(repo_id:, replace_existing: true)` | Takes an update. The new bundle is downloaded and verified **before** the old one is replaced, so a failed transfer leaves the working one in place; the replaced revision is then reclaimed. |
| `verify_model(model_type:, repository:)` | Re-checks a staged bundle against what was published. Reports; never deletes. |
| `repair_model(model_type:, repository:)` | Re-stages a bundle that no longer verifies. May download. |

```dart
final updates = await TheStageFlutterSDK.available_updates();
if (updates.isNotEmpty && await userAgreesToDownload()) {
  for (final u in updates) {
    // Null for an AI pack or a local bundle: those update with
    // your app, not through the SDK.
    final repo = u.repository;
    if (repo == null) continue;
    // A model being replaced must not be loaded: stop yours first.
    await TheStageFlutterSDK.prefetch_model(
      repo_id: repo,
      replace_existing: true,
    );
  }
}
```

Several repos can share a model type — every text LLM is
`the-stage-llm` — and each is installed separately, so a device can
hold several at once and switching between them reads from disk. Each
update names its `repository`, and `update_available`,
`remove_model`, `verify_model` and `repair_model` take `repository:`
to say which one you mean; without it the SDK picks one.

### Result types

Kotlin fields are snake_case. In Dart, `InstalledModel` and
`ModelUpdate` fields are camelCase; `SlotIntegrity` and `SweepResult`
use the same names as Kotlin.

**`InstalledModel`** (`installed_models()`)

| Kotlin | Dart | Meaning |
|---|---|---|
| `model_type` | `modelType` | Model type, e.g. `the-stage-llm` |
| `variant` | `variant` | SoC variant the bundle was staged for |
| `source` | `source` | How it arrived: `hf`, `aipack` or `local` (Kotlin `HF` / `AI_PACK` / `LOCAL`) |
| `identity` | `identity` | Commit (`hf`), release tag (`aipack`) or source stamp (`local`); compare for equality, never parse |
| `repository` | `repository` | HF repo it was downloaded from; null otherwise |
| `source_repo` | `sourceRepo` | Repo the bundle was built from, as it declares; null when it carries no manifest |
| `slot` | `slot` | Path of the extracted bundle |
| `bytes` | `bytes` | Size of the extracted tree |
| `archive` / `archive_bytes` | `archive` / `archiveBytes` | A downloaded archive kept beside the tree, and its size |
| `retained_reason` | `retainedReason` | Why that archive was kept |
| `content_sha256` | `contentSha256` | Archive hash, for an HF download; null for a pack |
| `built_at` | `builtAt` | When the bundle was built (ISO-8601 UTC), as it declares |
| `declared_identity` | `declaredIdentity` | What the app last asked for; differs from `identity` while a new pack tag waits |
| `declared_source` | `declaredSource` | Route the app last named; differs from `source` while a route change is pending |
| `hf_revision` | `hfRevision` | The commit, when known; null is a real answer |
| `play_copy_retained` | `playCopyRetained` | Play also holds the pack's copy, so removing the model frees `bytes` and no more |
| `installed_at` | `installedAt` | When it was staged, epoch milliseconds |
| `total_bytes` | `totalBytes` | Tree plus any kept archive |

**`ModelUpdate`** (`available_updates()`, `update_available()`)

| Kotlin | Dart | Meaning |
|---|---|---|
| `model_type` | `modelType` | Model type |
| `variant` | `variant` | SoC variant |
| `repository` | `repository` | Repo the update is about; null for an AI pack or a local bundle |
| `installed` | `installed` | What is on the device |
| `available` | `available` | What this build names |
| `kind` | `kind` | `revision`: both are commits. `tag`: both are AI-pack release tags. `route`: both are delivery routes (`hf`, `aipack`, `local`), meaning the next load transfers the bundle again from the other route. Kotlin `UpdateKind.REVISION` / `TAG` / `ROUTE`, Dart `UpdateKind.revision` / `tag` / `route` |

`installed` and `available` are only comparable within one `kind`.

**`SlotIntegrity`** (`verify_model()`)

| Field | Meaning |
|---|---|
| `verified` | The bundle matched what was published |
| `verifiable` | False when the bundle carries no integrity data — not corruption, and not a reason to repair |
| `reason` | Null when verified; otherwise `not_staged`, `not_verifiable`, `check_failed` or `check_error` |

**`SweepResult`** (`maintain()`)

| Field | Type | Meaning |
|---|---|---|
| `freed_bytes` | `Long` (Dart `int`) | Bytes freed |
| `removed_paths` | `Int` (Dart `int`) | Number of files and directories removed — a count, not a list of paths |

## Reclaiming space

Models live in your app's private files, which Android never clears
on its own, so they stay until the SDK removes them or the app is
uninstalled.

| Call | Frees |
|---|---|
| `remove_model(model_type:, repository:)` | One installed model. Throws while it is loaded; stop it first. It downloads again on its next load. |
| `maintain()` | Everything nothing claims: revisions an update replaced, models your app no longer loads, and downloads abandoned more than a day ago. Safe to call at any time; loaded models are never touched. Returns a `SweepResult`: `freed_bytes` and the `removed_paths` count. |
| `reset_models()` | Every staged model and the download cache, to start over. Throws while any model is loaded. A `prefetch_model` in flight is aborted, not waited for. |

The SDK already reclaims the replaced revision right after each
update, so an app that never calls `maintain()` does not keep one copy
per update. Put `maintain()` behind a "free up space" action, or call
it after dropping a model from your app.

For a model delivered as a Play AI pack, `remove_model` frees the
extracted copy; a pack Play itself still holds stays with Play (the
`play_copy_retained` field of `installed_models()` says so —
`playCopyRetained` in Dart).

## Storage

Delivery needs more free space than the bundle's download size. The
downloaded archive stays on disk while the extracted tree is written
beside it, and parts of the bundle are prepared one at a time while
their packed source is still present. Peak usage is therefore roughly
**download size + extracted size**, not either alone.

The SDK checks this before a transfer starts and again before
extraction, and fails fast with `INSUFFICIENT_STORAGE` (see
[logging.md](./logging.md)) rather than letting the volume fill. A
write to a full volume can block in the kernel instead of returning an
error, so an unguarded load would appear to hang with no diagnostic.

A device that is low on space is therefore refused the model up front
instead of failing partway through. Surface the error to the user — it
is the one load failure they can act on.

## Handling storage and in-use errors

Low storage fails `start_model` and `prefetch_model`. Removing a
loaded model (`remove_model`, `reset_models`) fails with model-in-use;
stop the model and retry.

**Kotlin:**

```kotlin
import ai.thestage.qlip.ModelManagerError
import ai.thestage.qlip.delivery.EngineArchiveError

try {
    TheStageAI.start_model(model_name = "llm", engines_path = repo)
} catch (e: EngineArchiveError.InsufficientStorage) {
    // e.need_bytes, e.free_bytes: ask the user to free space.
}

try {
    TheStageAI.remove_model(model_type = "the-stage-llm")
} catch (e: ModelManagerError.ModelInUse) {
    // e.model_name is loaded: stop_model it first.
}
```

**Flutter:**

```dart
try {
  await TheStageFlutterSDK.start_model(
    model_name: 'llm', engines_path: repo,
  );
} on PlatformException catch (e) {
  if (e.code == 'INSUFFICIENT_STORAGE') {
    // Ask the user to free space; e.message has the sizes.
  }
}

try {
  await TheStageFlutterSDK.remove_model(model_type: 'the-stage-llm');
} on PlatformException catch (e) {
  // Model in use has no dedicated code: e.message names the
  // loaded model. stop_model it first.
}
```

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

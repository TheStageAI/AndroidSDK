# Shipping TheStage models via Google Play AI packs — integration guide

Audience: app teams consuming the TheStage Android SDK who want
model bundles delivered by Google Play (Play for On-device AI /
Play Asset Delivery) instead of — or in addition to — the default
Hugging Face download.

What you get: Play hosts the models for free inside your AAB,
pre-downloads them right after install (fast-follow) or on first
use (on-demand), serves each phone only the variant matching its
SoC, and delta-patches across app updates. The SDK API is
unchanged — only the `engines_path` string differs.

---

## 1. Choose the source per model

| | Hugging Face (default) | AI pack |
|---|---|---|
| Model update | Anytime, no app release | Rides your app release |
| Hosting | TheStage HF repos | Google Play (free) |
| First download | On first `start_model` | At install (fast-follow) or first use |
| Works on sideloads / non-Play stores | yes | no (use fallback) |
| SoC variant selection | SDK runtime detection | Play device catalog |

Both can be mixed in one app, per model. An AI-pack model can also
declare an HF fallback so sideloaded installs still work (§6).

Decision matrix per model:

- **Large NPU model (100 MB+)** → AI pack, `on-demand` (+ optional
  first-launch `prefetch_model`), or `fast-follow` +
  `aipack_keep_pack: true` when the model must be ready in the
  first seconds after install.
- **Small CPU-only model (a few MB — silero-vad, smart-turn, ...)**
  → skip packs entirely: bundle the `engines.zip` as an ordinary
  app asset, copy it once to app storage at first run, and pass
  that path as `engines_path` (a local path is a first-class
  source). Flutter:

  ```dart
  Future<String> stageAsset(String asset, String name) async {
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}/$name');
    if (!f.existsSync()) {
      final bytes = await rootBundle.load(asset);
      await f.writeAsBytes(bytes.buffer.asUint8List());
    }
    return f.path;
  }
  // engines_path: await stageAsset('assets/vad_engines.zip',
  //                                'vad_engines.zip')
  ```

- **Model whose updates must NOT wait for app releases** → keep it
  on Hugging Face.

## 2. Prerequisites

- Android Gradle Plugin **8.10+** (device targeting needs it).
- `gradle.properties`:
  `android.experimental.enableDeviceTargetingConfigApi=true`
- **Required for NPU models** — AAB installs keep native libs
  compressed by default, which breaks the Qualcomm DSP loader and
  silently drops inference to CPU. In `app/build.gradle`:

  ```kotlin
  android {
      packaging { jniLibs { useLegacyPackaging = true } }
  }
  ```
- Flutter apps: nothing else — the `thestage_android_sdk` plugin
  carries the `com.google.android.play:ai-delivery` dependency
  transitively. Native-AAR integrations add it themselves:
  `implementation "com.google.android.play:ai-delivery:0.1.1-alpha01"`
- App must ship as an **AAB** through Play (packs never work in a
  plain APK — sideloads take the fallback path).

## 3. Get the model files

For each model you license, TheStage provides the same per-SoC
bundles that back the HF path:

```
engines_qualcomm_sm8550.zip   (Snapdragon 8 Gen 2)
engines_qualcomm_sm8650.zip   (Snapdragon 8 Gen 3)
engines_qualcomm_sm8750.zip   (Snapdragon 8 Elite)
engines_qualcomm_sm8850.zip   (Snapdragon 8 Elite Gen 5)
engines_cpu.zip               (fallback, if available)
```

Each release comes with a **release tag** (e.g. `whisper-0.2.3`).
You will need it in §6.

## 4. Create one AI pack module per model

Layout (example: whisper):

```
your-app/
├── settings.gradle(.kts)        # include(":thestageai_models_whisper")
├── app/
└── thestageai_models_whisper/
    ├── build.gradle.kts
    └── src/main/assets/
        ├── thestageai_models_whisper#group_sm8550/engines.zip
        ├── thestageai_models_whisper#group_sm8650/engines.zip
        ├── thestageai_models_whisper#group_sm8750/engines.zip
        ├── thestageai_models_whisper#group_sm8850/engines.zip
        └── thestageai_models_whisper#group_other/engines.zip
```

Drop each per-SoC zip into its
`<packName>#group_<soc>/` directory under the name `engines.zip`.
The asset dir is **named after the pack** — required as soon as
the AAB carries more than one pack: packs are built
fusing-enabled, so bundletool rejects identical bare paths across
modules (`EntryClash`). One naming rule for every delivery mode. The
`#group_` suffix is Play routing metadata — it is stripped on
delivery, so at runtime the device sees
`<packName>/engines.zip` containing its own variant. The SDK
routes nothing here; Play's device catalog does.

`thestageai_models_whisper/build.gradle.kts`:

```kotlin
plugins { id("com.android.ai-pack") }

aiPack {
    packName.set("thestageai_models_whisper")
    dynamicDelivery {
        // "fast-follow": auto-downloads right after install.
        // "on-demand": downloads on first start_model.
        // "install-time": small packs only — see the note
        // below §6; use assets/<packName>#group_<soc>/ as
        // the asset dir so multiple install-time packs
        // don't collide in the merged asset namespace.
        deliveryType.set("on-demand")
    }
}
```

## 4b. Install-time packs (small models)

For a small model that must be present from the very first launch
(no download, works offline immediately), use an install-time pack.
Two differences from §4: the delivery type, and the asset dir is
named after the pack (REQUIRED — install-time assets merge into one
shared namespace, and the pack-named dir keeps multiple packs from
colliding):

```
thestageai_models_vad/
├── build.gradle.kts
└── src/main/assets/
    ├── thestageai_models_vad#group_sm8550/engines.zip
    ├── thestageai_models_vad#group_sm8650/engines.zip
    ├── thestageai_models_vad#group_sm8750/engines.zip
    ├── thestageai_models_vad#group_sm8850/engines.zip
    └── thestageai_models_vad#group_other/engines.zip
```

(One SoC-independent bundle? Use a single unsuffixed dir
`thestageai_models_vad/engines.zip` — no groups needed.)

```kotlin
aiPack {
    packName.set("thestageai_models_vad")
    dynamicDelivery {
        deliveryType.set("install-time")
    }
}
```

Start it exactly like any other source — the SDK detects the
install-time pack and stages it from the APK automatically:

```dart
await TheStageFlutterSDK.start_model(
  model_type: 'silero-vad',
  model_name: 'silero_vad',
  engines_path: 'aipack://thestageai_models_vad',
  config: {'aipack_release_tag': 'vad-1.0.0'},
);
```

`aipack_keep_pack` / `aipack_fallback_repo` are meaningless here
(the pack is part of the APK and present on every install,
including sideloads of a universal APK). The release tag works the
same as §6: bump it only when the model files change, and app
updates cost zero re-staging otherwise. Size discipline: the pack
is a permanent part of the install — keep it to tens of MB.

## 5. Wire the app module

`app/build.gradle.kts`:

```kotlin
android {
    assetPacks += listOf(
        ":thestageai_models_whisper",
        // ...one entry per model pack
    )
    bundle {
        deviceTargetingConfig =
            file("device_targeting_config.xml")
        deviceGroup {
            enableSplit = true
            defaultGroup = "other"
        }
    }
}
```

Before locking the config, enumerate the exact SoC strings in Play
Console's **Device Catalog** (searchable by SoC): matching is exact
— no wildcards — so binned variants (`SM8650-AC` etc.) each need
their own selector line alongside the base part number.

`app/device_targeting_config.xml` (shared by all packs; both
manufacturer spellings are required — devices report either):

```xml
<config:device-targeting-config
    xmlns:config="http://schemas.android.com/apk/config">
  <config:device-group name="sm8550">
    <config:device-selector>
      <config:system-on-chip manufacturer="QTI" model="SM8550"/>
    </config:device-selector>
    <config:device-selector>
      <config:system-on-chip manufacturer="Qualcomm" model="SM8550"/>
    </config:device-selector>
  </config:device-group>
  <!-- repeat for sm8650 / sm8750 / sm8850 -->
</config:device-targeting-config>
```

## 6. Start the model

Identical to the HF flow except for `engines_path`:

```dart
await TheStageFlutterSDK.start_model(
  model_type: 'whisper',
  model_name: 'whisper',
  engines_path: 'aipack://thestageai_models_whisper',
  config: {
    // Release tag of the bundles inside the pack. Bump it
    // when (and only when) you ship new model files; an
    // app update with an unchanged tag reuses the already
    // extracted model with zero downloads.
    'aipack_release_tag': 'whisper-0.2.3',

    // true  -> keep Play's copy after extraction.
    //          REQUIRED for fast-follow packs.
    // false -> release it (default; on-demand packs only).
    'aipack_keep_pack': false,

    // Optional: sideloads / unmatched devices / fetch
    // failures fall back to the normal HF download.
    'aipack_fallback_repo':
        'TheStageAI/thewhisper-large-v3-turbo',
  },
);
```

Download progress arrives on the same progress stream as HF
downloads (0..1 fraction).

Rules of thumb:

- `on-demand` + `aipack_keep_pack: false` — default. 1x disk;
  the Play copy is released after extraction; re-downloads happen
  only when `aipack_release_tag` changes.
- `fast-follow` + `aipack_keep_pack: true` — best first-open UX
  (model is on the phone before first launch), costs 2x disk.

Why fast-follow requires `keep_pack: true`: fast-follow is a
*declarative* contract — "Play, keep this pack present on the
device". Play honors it not just at install but at every app
update: if the pack is missing at update time (because the SDK
removed it), Play re-syncs to the declared state and re-downloads
the whole pack — even when its content did not change. Removing a
fast-follow pack therefore buys nothing (Play restores it) and
costs a full pack download on every update (verified on a Play
internal test track). With `keep_pack: true` the kept copy is
delta-patched across updates instead. If the 2x disk bothers you,
the right lever is switching the pack to `on-demand`, where
removal sticks — not removing a fast-follow pack.

Fast-follow UX at 1x disk: the only thing fast-follow adds over
on-demand is that the download starts between install and first
open. You can get within a hair of that with `on-demand` +
calling `prefetch_model(repo_id: 'aipack://...')` fire-and-forget
as soon as the app first starts (behind your onboarding/splash
flow). The model downloads while the user is still getting set up,
removal sticks (1x disk), and updates cost zero while the release
tag is unchanged. The residual gap: the download cannot begin
until the first app open with network, so a user who reaches the
model feature within the first seconds of the very first run may
still see the download progress. Pick fast-follow + keep only if
that gap is unacceptable.

`install-time` — small packs only. Install-time packs are fused
into the installed APK set: the bytes become a permanent part of
the app image (`removePack()` doesn't apply — 2x disk forever),
they count against the 4 GB base-app cap, inflate the store-listed
install size, and delay install completion. For 100 MB+ models
that's disqualifying — use on-demand or fast-follow. For a SMALL
per-SoC model (tens of MB) it's a fine trade: guaranteed presence
from the very first launch, no fetch, no network dependency. The
SDK handles install-time packs transparently (same `aipack://`
path — it stages the archive from the APK's assets once per
release tag). Keep the pack's asset dir named after the pack
(`<packName>#group_<soc>/engines.zip`) so several install-time
packs can coexist — the pack-named dir is REQUIRED for
install-time packs (the bare `engines/` layout is only for
on-demand/fast-follow, whose files arrive at a private per-pack
location). Small models with NO per-SoC variants don't need a
pack at all — see the §1 decision matrix.

## 7. Large downloads off Wi-Fi / metered networks

Play schedules pack downloads as **unmetered-only** by default, so
a fetch can park instead of running:

- On **cellular**, a >200 MB download needs the user's OK to use
  mobile data. Play surfaces a system confirmation in the
  notification shade; until the user taps it, the fetch waits.
- On a Wi-Fi network flagged as **metered** (phone hotspots, some
  corporate networks), the fetch waits for an unmetered network.

The SDK surfaces both as a `status` on the progress stream so your
app can react instead of showing a spinner that looks hung
(`progress` goes negative and should be ignored while `status` is
set):

```dart
TheStageFlutterSDK.on_progress.listen((e) {
  switch (e['status']) {
    case 'waiting_for_confirmation':
      // >200 MB on cellular — show Play's own dialog (below).
      _promptCellularConfirmation();
    case 'waiting_for_wifi':
      // Ask the user to connect to Wi-Fi.
      _showWaitingForWifi();
    default:
      _showProgress(e['progress'] as double); // 0..1
  }
  // A waiting event carries `status` and no `progress`; a
  // progress event carries `progress` and no `status`.
});
```

### Showing Play's cellular confirmation dialog

The confirmation dialog is an Activity UI flow, so trigger it from
your app (not the SDK). Two setup requirements (both verified on a
Flutter app):

1. **Declare the dependency in your app** — the plugin ships
   ai-delivery as `implementation` (runtime only), so your app
   can't compile against `AiPackManager` unless it declares it too.
   In `app/build.gradle(.kts)`:
   `implementation("com.google.android.play:ai-delivery:0.1.1-alpha01")`
2. **Use `FlutterFragmentActivity`, not `FlutterActivity`** —
   `registerForActivityResult` (and thus
   `showConfirmationDialog(launcher)`) needs a ComponentActivity;
   the default `FlutterActivity` extends plain `Activity`.

```kotlin
class MainActivity : FlutterFragmentActivity() {
    // Registered at Activity creation (a launcher can't be made
    // on demand). The paused fetch resumes on approval, so the
    // callback body is empty.
    private val aiPackConfirm = registerForActivityResult(
        ActivityResultContracts.StartIntentSenderForResult()
    ) { /* fetch resumes automatically */ }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(
            engine.dartExecutor.binaryMessenger, "app/aipack"
        ).setMethodCallHandler { call, result ->
            if (call.method == "showConfirmation") {
                result.success(
                    AiPackManagerFactory.getInstance(this)
                        .showConfirmationDialog(aiPackConfirm)
                )
            } else result.notImplemented()
        }
    }
}
```

Invoke `MethodChannel('app/aipack').invokeMethod('showConfirmation')`
from the `waiting_for_confirmation` / `waiting_for_wifi` branch
above. (The dialog acts on the app's pending downloads, so it
works even though the SDK started the fetch; no `start_model`
restart needed.)

Alternative: sidestep the whole path by pre-fetching on Wi-Fi at
onboarding (`prefetch_model` with the `aipack://` path) so the
model is already present before the user needs it.

Normal download progress arrives on the same stream (0..1), same
as HF downloads — verified end-to-end on a Play internal track.

## 7b. Availability check

`check_model_availability` accepts `aipack://` paths like any other
source — usable before `initialize`, no token, no download — and it
covers every delivery type through one query: an install-time pack
or a completed fast-follow / on-demand fetch reports as delivered;
a not-yet-delivered on-demand / fast-follow pack reports as
fetchable.

- **`availability`** is **`local`** when the pack is already on the
  device (install-time, or a completed fetch) — it loads offline.
  It is **`remote`** when the pack is fetchable but not yet on the
  device (an on-demand / fast-follow download still pending); in
  that `remote` case `bundleSizeBytes` carries Play's reported
  download size (the one thing knowable before the fetch). It is
  **`none`** when the pack is absent or a fetch failed.
- **`reason`** is **`aipack_pack`** on any available result
  (`local` or `remote`), and **`variant_unavailable`** when the
  pack is absent / unknown to Play. (`network_unreachable` is
  reported for a transient probe error — no Play services on the
  device, or a service error — meaning "unknown", not "absent".)
- **`compute`** is always **null** for an AI pack. Play does not
  expose the delivered variant/group to the client — no
  AssetPackManager / AiPackManager API returns it — so the SDK
  does not claim a `compute` it cannot verify. This is the same
  contract as any local bundle; `compute` is only ever populated
  on the HF path, which probes the exact published variant. If
  your app needs to know the group *before* download, that is a
  curation choice on your side (per-group pack names, or a curator
  manifest you ship alongside the packs), not something the SDK
  can probe.

```dart
final r = await TheStageFlutterSDK.check_model_availability(
  model_path: 'aipack://thestageai_models_whisper',
);
switch (r.availability) {
  case ModelAvailability.local:
    // Pack already on the device — loads offline.
    break;
  case ModelAvailability.remote:
    // Fetchable; r.bundleSizeBytes is Play's download size.
    break;
  case ModelAvailability.none:
    // Absent or failed — inspect r.reason.
    break;
  default:
    break;
}
// On any available result the reason is aipack_pack (raw wire
// value 'aipack_pack'); compute is null — the SDK can't see the
// delivered SoC group.
final available = r.reason == AvailabilityReason.aipackPack;
```

## 8. Testing

Local, no Play account (bundletool 1.18+):

```bash
./gradlew :app:bundleRelease
java -jar bundletool.jar build-apks \
    --bundle=app/build/outputs/bundle/release/app-release.aab \
    --output=app.apks --local-testing
java -jar bundletool.jar install-apks --apks=app.apks \
    --device-groups=sm8750     # simulate the group match
```

Local-testing caveats: fast-follow behaves as on-demand, and the
real SoC group matching is bypassed (`--device-groups` picks it).
Install-time packs install normally in local testing (they're
ordinary split APKs), so both routes are locally testable.
Always finish with one pass on a Play **internal test track** —
it exercises true fast-follow, device-catalog matching, and
update patching. Internal testing needs no review and no public
listing.

## 9. Behavior across app updates

- Model files unchanged (same `aipack_release_tag`): the SDK keeps
  serving its extracted copy; Play keeps/patches its pack copy (if
  kept). Zero model bytes downloaded.
- Model files changed (new tag): the SDK re-fetches the pack once
  and re-extracts. With fast-follow the new pack is typically
  already on the phone before the app first opens.
- Never persist the pack's `assetsPath` yourself — it changes
  every app version. The SDK re-resolves it on each start.

## 10. Complete example (one on-demand model, with the dialog)

Everything above assembled for a single on-demand model
(`whisper`). Copy this, then read the sections for detail.

### File tree
```
my-app/
├── settings.gradle.kts
├── android/                         # (Flutter app's android/)
│   ├── gradle.properties
│   ├── app/
│   │   ├── build.gradle.kts
│   │   ├── device_targeting_config.xml
│   │   └── src/main/kotlin/.../MainActivity.kt
│   └── thestageai_models_whisper/
│       ├── build.gradle.kts
│       └── src/main/assets/
│           ├── thestageai_models_whisper#group_sm8550/engines.zip
│           ├── thestageai_models_whisper#group_sm8650/engines.zip
│           ├── thestageai_models_whisper#group_sm8750/engines.zip
│           ├── thestageai_models_whisper#group_sm8850/engines.zip
│           └── thestageai_models_whisper#group_other/engines.zip
└── lib/main.dart
```

### settings.gradle.kts
```kotlin
plugins {
    id("com.android.application") version "8.10.1" apply false
    id("com.android.ai-pack") version "8.10.1" apply false
}
include(":app", ":thestageai_models_whisper")
```

### gradle.properties
```
android.experimental.enableDeviceTargetingConfigApi=true
```

### thestageai_models_whisper/build.gradle.kts
```kotlin
plugins { id("com.android.ai-pack") }
aiPack {
    packName.set("thestageai_models_whisper")
    dynamicDelivery { deliveryType.set("on-demand") }
}
```

### app/build.gradle.kts (relevant parts)
```kotlin
android {
    assetPacks += listOf(":thestageai_models_whisper")
    bundle {
        deviceTargetingConfig = file("device_targeting_config.xml")
        deviceGroup { enableSplit = true; defaultGroup = "other" }
    }
    packaging { jniLibs { useLegacyPackaging = true } }
}
dependencies {
    implementation("com.google.android.play:ai-delivery:0.1.1-alpha01")
}
```

### app/device_targeting_config.xml
```xml
<config:device-targeting-config
    xmlns:config="http://schemas.android.com/apk/config">
  <config:device-group name="sm8750">
    <config:device-selector>
      <config:system-on-chip manufacturer="QTI" model="SM8750"/>
    </config:device-selector>
    <config:device-selector>
      <config:system-on-chip manufacturer="Qualcomm" model="SM8750"/>
    </config:device-selector>
  </config:device-group>
  <!-- repeat for sm8550 / sm8650 / sm8850 -->
</config:device-targeting-config>
```

### MainActivity.kt (dialog host)
```kotlin
class MainActivity : FlutterFragmentActivity() {
    private val confirm = registerForActivityResult(
        ActivityResultContracts.StartIntentSenderForResult()
    ) { /* fetch resumes automatically */ }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(
            engine.dartExecutor.binaryMessenger, "app/aipack"
        ).setMethodCallHandler { call, result ->
            if (call.method == "showConfirmation")
                result.success(
                    AiPackManagerFactory.getInstance(this)
                        .showConfirmationDialog(confirm))
            else result.notImplemented()
        }
    }
}
```

### lib/main.dart (the whole runtime flow)
```dart
const _channel = MethodChannel('app/aipack');
var _dialogShown = false;

Future<void> loadWhisper() async {
  TheStageFlutterSDK.on_progress.listen((e) {
    final status = e['status'] as String?;
    if (status == 'waiting_for_wifi' ||
        status == 'waiting_for_confirmation') {
      if (!_dialogShown) {
        _dialogShown = true;
        _channel.invokeMethod('showConfirmation'); // Play's dialog
      }
      setDownloadLabel('Confirm mobile-data download…');
    } else {
      _dialogShown = false;
      setDownloadProgress(e['progress'] as double); // 0..1, present
    }                                                // on progress events
  });

  await TheStageFlutterSDK.start_model(
    model_type: 'whisper',
    model_name: 'whisper',
    engines_path: 'aipack://thestageai_models_whisper',
    config: {'aipack_release_tag': 'whisper-1.0.0'},
  );
  // Model ready on the NPU. On cellular: fetch parks → dialog →
  // approve → resumes → loads. On Wi-Fi: downloads → loads.
}
```

That is the entire integration: five short config files, one
Activity, and one Dart function. Adding more models = one more pack
module + one more `start_model` call.

# Licensing & Device Identity

How seats work when your app embeds the SDK, and what that means for
your code: one `initialize` call per app launch, online, and inference
on the device after that. Commercial terms are in
[Product Terms](./product_terms.md).

> **Main features**
>
> - **One call**: `initialize(api_token)` registers the device and
>   unlocks every pipeline.
> - **Online at launch**: the token is validated online once per app
>   process; inference itself runs on the device.
> - **Stable seats**: reinstalling the same app on the same device keeps
>   the same seat.

## Quick start

**Kotlin**

```kotlin
import ai.thestage.qlip.TheStageAI

// Once, at app start (e.g. Application.onCreate).
TheStageAI.registerContext(context)

// Once per process, before any start_model. Suspends while the
// token is validated online.
TheStageAI.initialize(api_token = token)
```

**Flutter**

```dart
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

// Once per process, before any start_model. The plugin registers
// the context itself.
await TheStageFlutterSDK.initialize(api_token: token);
```

### Important API

| Term | Meaning |
|---|---|
| **Seat** | One `(apiToken, deviceId)` pair. Two tokens on one phone are two seats; one token on two phones is two seats. |
| **`apiToken`** | Identifies your organisation. Generate it at [app.thestage.ai](https://app.thestage.ai/) → Profile → API tokens. The SDK does not store it. |
| **`deviceId`** | Identifies the registered device for that token. Survives reinstalls and "clear data" of the same app; a factory reset gives a new one. |
| **Validation** | `initialize` checks the token online. It holds for the rest of the process; the next app launch checks again. There is no offline grace period. |

## Usage Guides

### Keep the token out of the binary

> **Problem**
>
> **Building** — any shipping app.
>
> **Users want** — nothing; this is for you — the token must not be in
> git or readable from the APK.
>
> **Hard part** — `initialize` needs the token at runtime, so it has
> to come from somewhere the build controls.

**Solution — what to use**

- A Gradle property or environment variable → `BuildConfig` field.
- Flutter: `--dart-define-from-file=secrets.json` →
  `String.fromEnvironment`.
- `.gitignore` the secrets file.
- Or fetch it from your backend on first launch.

**Kotlin**

```kotlin
// build.gradle.kts: buildConfigField("String", "TS_API_TOKEN", ...)
TheStageAI.initialize(api_token = BuildConfig.TS_API_TOKEN)
```

**Flutter**

```dart
// flutter run --dart-define-from-file=secrets.json
const token = String.fromEnvironment('TS_API_TOKEN');
await TheStageFlutterSDK.initialize(api_token: token);
```

> [!TIP]
> - Add `secrets.json` to `.gitignore`.
> - Rotating a token does not change seats already registered.

### Use the models where the network is unreliable

> **Problem**
>
> **Building** — a field-service app used where the signal comes and
> goes.
>
> **Users want** — dictation and transcription keep working on site.
>
> **Hard part** — the token is validated online at every app launch,
> and the models download online.

**Solution — what to use**

- `initialize` at launch, while there is a connection; it fails
  without one, so retry it when the network returns.
- `prefetch_model` every model the app needs during onboarding.
- After a successful `initialize`, starting a downloaded model and
  running inference need no network for the rest of the process. Keep
  the process alive (a foreground service) rather than relaunching
  in the field.

**Kotlin**

```kotlin
// Onboarding, online:
TheStageAI.initialize(api_token = token)
TheStageAI.prefetch_model(repo_id = "TheStageAI/thewhisper-large-v3-turbo")
```

**Flutter**

```dart
await TheStageFlutterSDK.initialize(api_token: token);
await TheStageFlutterSDK.prefetch_model(
  repo_id: 'TheStageAI/thewhisper-large-v3-turbo');
```

> [!TIP]
> - A fresh launch with no network cannot start any model: handle the
>   `initialize` error and retry when connectivity returns.
> - First-run download needs network regardless — do it on onboarding.

## Device integrity

A release build of your app does not load models on a device that
looks compromised; a debuggable build always loads. A release-signed
test app that needs a debugger attached can allow it with a manifest
flag — never ship this in a production build:

```xml
<application ...>
    <meta-data
        android:name="ai.thestage.qlip.ALLOW_DEBUGGER"
        android:value="true" />
</application>
```

## Model initializations

When a model starts, the SDK counts that start with the backend for
per-model usage: the API token, the `deviceId` and the model's id. No
prompts, audio, outputs or other user content are sent. The count
never delays or fails the start; when the device is offline it is sent
later.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `start_model` fails with "not initialized" | `initialize` not awaited before it. | Await it first, once per process. |
| `initialize` fails at launch with no network | The token is validated online at every launch. | Retry when connectivity returns. |
| `initialize` fails on a corporate network | A proxy that intercepts TLS with its own certificate. | Let the app connect directly. |
| A release test build refuses to load under a debugger | The device integrity check. | Add the `ALLOW_DEBUGGER` flag above to the test build only. |
| Seat count higher than devices | Multiple tokens in use, or test tokens on production devices. | One token per app; open a Service Request at [app.thestage.ai/contact](https://app.thestage.ai/contact) for plan questions. |

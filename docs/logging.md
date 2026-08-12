# Logging & Diagnostics

The SDK keeps a lightweight, consumer-safe diagnostics surface so a
host app can watch the SDK's lifecycle during development and pull a
support blob from a release build. Every surface below carries the
same invariant: **no user content is ever logged** — no prompts, no
transcripts, no captions, no tokens — and absolute filesystem paths
are sanitized down to their last two components before they leave the
SDK.

## What gets logged

Lifecycle events worth seeing in a shipped build: model load / unload,
HuggingFace download, cache hits, recovery, coarse timings, thermal
transitions, and recorded error causes. Fine-grained per-step traces
and micro-timings sit below the shipped floor (see
[Log levels](#log-levels)) and are compiled out of production builds.

## Kotlin surface (`TheStageAI`)

The singleton owns a bounded in-memory **log ring** (up to 128 recent
lines, oldest dropped) plus a per-session file sink. Three entry points:

```kotlin
import ai.thestage.qlip.TheStageAI

// 1) Snapshot the recent ring (e.g. to attach to a support ticket).
val lines: List<String> = TheStageAI.recent_logs()

// 2) Attach a live listener — every new line is forwarded here in
//    addition to the ring, the session file, and logcat. Pass null
//    to detach. Lines are already path-sanitized and user-content
//    free.
TheStageAI.set_log_listener { line ->
    // append to your own console / on-screen log
}

// 3) Push your own diagnostic line into the ring (path-sanitized).
TheStageAI.record_log("app: user tapped Generate")
```

Each ring entry is prefixed with a wall-clock `[HH:MM:SS.mmm]`
timestamp so it stays meaningful hours later in a pasted support chat.

### Recording error causes

On a non-debuggable (release) build there is no `adb logcat` to read,
so record the cause of a caught failure and surface it to support:

```kotlin
try {
    TheStageAI.infer(model_name = "llm", input_json = ...)
} catch (e: Throwable) {
    TheStageAI.record_error(e.message, code = TheStageAI.SDK_ERROR_LLM_GENERATE_FAILED)
}

// Later, from a diagnostics screen:
val cause = TheStageAI.last_error        // path-sanitized message, or null
val code  = TheStageAI.last_error_code   // symbolic category, or null
```

`record_error` pushes an `[error]` entry into the ring and stores the
most recent message + code. Branch your UI on the symbolic code rather
than parsing the message text, which may evolve across SDK versions.
Known codes: `SDK_ERROR_INPUT_TOO_LONG`, `SDK_ERROR_SENTENCE_TOO_LONG`,
`SDK_ERROR_LLM_GENERATE_FAILED`, `SDK_ERROR_LLM_LOAD_FAILED`,
`SDK_ERROR_MODEL_UNAVAILABLE`.

## Session log file

The ring is also mirrored to a plaintext file so a session's lifecycle
trail survives after the app is closed and can be pulled for support:

```
<app filesDir>/thestage_logs/session-<yyyyMMdd-HHmmss>.log
```

The SDK keeps only the **5 most recent** session files (older ones are
pruned on the next session). The file holds exactly the same
path-sanitized, user-content-free lines the ring holds — nothing about
encryption or key material is ever written.

## Flutter surface

The plugin exposes the SDK's diagnostics ring on a `logs`
EventChannel (`thestage_android_sdk/logs`). On subscribe it replays the
current ring so a late subscriber still sees the session's history, then
streams new lines live.

`TheStageFlutterSDK.initialize` wires this up automatically via
`ensureDeveloperLogs()`, which `debugPrint`s each line so SDK lifecycle
shows up in the `flutter run` console (otherwise it lives only in
`adb logcat`). It is a **no-op in release builds** and idempotent:

```dart
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

// Called for you by initialize(); call it earlier if you want the
// pre-initialize lines too.
TheStageFlutterSDK.ensureDeveloperLogs();

await TheStageFlutterSDK.initialize(api_token: 'your-api-token');
```

To render the stream in your own UI (rather than the debug console),
listen to the channel directly:

```dart
import 'package:flutter/services.dart';

const _logs = EventChannel('thestage_android_sdk/logs');

_logs.receiveBroadcastStream().listen((line) {
  // append `line as String` to an on-screen log view
});
```

## Log levels

Internal logcat output is gated behind a compile-time floor
(`VERBOSE < DEBUG < INFO < WARN`). Production AARs ship at **INFO**:
lifecycle events are visible in `adb logcat`, while dev probes and
per-step traces are stripped from the bytecode entirely — a shipped
build has nothing for a consumer to reflectively re-enable. Real errors
are always emitted. The diagnostics ring / session file / `logs`
channel described above are populated **regardless of the logcat floor**,
so support dumps stay useful even on a quiet release build.

## Agent checklist

- Use `recent_logs()` / the session file / `record_error` for support;
  never ask a user for their API token.
- Every logged line is path-sanitized and free of user content — do not
  route prompts, transcripts, or captions into these sinks from app code.
- Flutter: rely on `ensureDeveloperLogs()` in debug; subscribe to the
  `thestage_android_sdk/logs` channel to render logs in your own UI.
- The `logs` stream and session file are diagnostics only — they never
  carry encryption or key material.

# Licensing & Device Identity

How seats work when your app embeds the SDK: what registers a device,
what counts as one billable seat, and what an integrator must know
about device identity on Android. Commercial terms and pricing live in
[Product Terms](./product_terms.md); for a quote open a **Service
Request** at [app.thestage.ai/contact](https://app.thestage.ai/contact).

## Initialize registers the device

`initialize` must be called before any pipeline will load. A
successful `initialize` validates the API token online and registers
the device — that online validation is what creates (or re-confirms)
the seat.

| Surface | Call |
|---|---|
| Kotlin | `TheStageAI.registerContext(context)` then `TheStageAI.initialize(api_token = "...")` |
| Flutter | `await TheStageFlutterSDK.initialize(api_token: '...')` — the plugin registers the context automatically |

The SDK never persists the API token itself.

## Seat = `(apiToken, deviceId)`

A billable seat is the **pair** `(apiToken, deviceId)`:

- The `apiToken` identifies the customer/developer. Different
  developers always use different tokens, so two unrelated apps on the
  same physical device are billed separately — by token, regardless of
  device-id scope.
- The `deviceId` identifies the device. The same app on the same
  device keeps the same id across launches, reinstalls and "clear
  data".

## How `deviceId` is derived

| Source | Scope | Survives uninstall / clear data? | Resets on |
|---|---|---|---|
| Android `ANDROID_ID` (SSAID) | **Per (app, device)** | Yes | Factory reset |
| Fallback: random UUID in app-private prefs | **Per (app, install)** | No | Uninstall / clear data |

- The SDK reads `Settings.Secure.ANDROID_ID`. Since Android 8 the OS
  scopes it to the app's signing key and the device user, and keeps it
  across uninstall/reinstall and "clear data"; only a factory reset
  changes it.
- The raw `ANDROID_ID` never leaves the device: the SDK sends only an
  HMAC of it plus the app's package name, shaped as a UUID, so the id
  is scoped per app.
- When `ANDROID_ID` is unavailable, the SDK falls back to a random
  UUID in app-private storage. That id is per install: uninstall or
  "clear data" produces a new one, and the backend reconciles brief
  uninstall/reinstall cycles by reusing the existing seat within a
  reactivation window.
- No backup configuration is needed: the id is recomputed on every
  install, not restored.

## Model initializations

After a model loads successfully, the SDK registers that
initialization with the backend for per-model usage
counting. The request carries the API token, the `deviceId` and the
model's id — the repository its bundle was built from, as the bundle's
signed manifest declares (or the `engines_path` the app passed, for a
bundle without one). No prompts, audio, outputs or other user content
are sent. Re-using a model that is already running is not a new
initialization.

`start_model` waits for that one request to answer or fail, but its
outcome never fails the load. When the device is offline, the event
is queued in app-private storage (capped per model) and replayed
after the next successful registration; a rejected event is dropped.

## Offline / network

- The token is validated **online once per process** (cached
  in-memory); a fresh app launch always re-validates online. There is
  **no offline grace window** — the device must be reachable when
  `initialize` runs, and a transport failure or backend rejection is a
  hard init failure.
- Connections are certificate-pinned to well-known public roots, so
  corporate MITM proxies (custom interception CAs) will break
  validation.

## Device integrity (release builds)

On a **release** build (the embedding app is not debuggable) the SDK
runs a best-effort environment check before it loads any engine and
**refuses to load** on an obviously compromised device — rooted,
running under an emulator, under an instrumentation/injection
framework, or with a debugger attached. It is a deterrence layer; the
check never reveals which probe fired.

- **Debug builds** (`android:debuggable="true"`) never enforce, so
  development on emulators and under a debugger works normally.
- A **release** build that legitimately needs a debugger attached (an
  instrumented test app) can opt **only the debugger probe** out with a
  manifest flag. Root / emulator / injection probes still enforce:

  ```xml
  <application ...>
      <meta-data
          android:name="ai.thestage.qlip.ALLOW_DEBUGGER"
          android:value="true" />
  </application>
  ```

  This is for test apps only — do not ship it in a production build.

## Quick reference

| Scenario | Pair | Seats |
|---|---|---|
| Same app, same device, relaunch | unchanged | 1 |
| Reinstall or "clear data" | unchanged `deviceId` | 1 |
| Factory reset | new `deviceId` | new seat |
| Reinstall, fallback id (no `ANDROID_ID`) | new `deviceId` | server reuses the old seat within the reactivation window; otherwise a new seat |
| Two different developers' apps, one device | different tokens | 2 |
| App relaunch after a prior online validation | unchanged | 1 (re-validates online each launch) |

## Agent Checklist

- Always `initialize` before starting any pipeline — it registers the
  device (online validation).
- One seat = `(apiToken, deviceId)`; different tokens on one device
  are different seats.
- Do not invent your own device registry — the SDK owns device
  identity.
- Do not depend on internal ID derivation or backend field names —
  they are not part of the public contract.
- Pricing / quota changes → open a **Service Request** at
  [app.thestage.ai/contact](https://app.thestage.ai/contact).

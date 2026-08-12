# Licensing & Device Identity

How the SDK identifies a device for licensing/billing, what counts as
a "device" on Android, and the server-side contract the backend must
honor so that reinstalling an app is not over-counted.

## Billing key: `(apiToken, deviceId)`

Every `initialize(api_token = …)` validates online by POSTing
`{ userApiToken, deviceId }` to
`https://backend.thestage.ai/user-api/v1/validate-token/app-on-device`.
A billable seat is the **pair** `(apiToken, deviceId)`:

- The `apiToken` identifies the customer/developer. Different
  developers always use different tokens, so two unrelated apps on the
  same physical device are billed separately — by token, regardless of
  device-id scope.
- The `deviceId` identifies the device. It is stored so that the same
  app on the same device keeps the same id across launches.

The SDK never persists the API token itself.

## How `deviceId` is derived

Source: `security/DeviceIdentifier.kt`.

| Platform | `deviceId` source | Scope | Survives uninstall? |
|---|---|---|---|
| **Android** | Random `UUID.randomUUID()`, persisted in the app's private `SharedPreferences` (`ai.thestage.qlip.sdk` / key `device_id`) | **Per (app, device install)** | Only with Android Auto Backup enabled |

Why a per-install SharedPreferences UUID:

- Android exposes no reliable, stable, cross-app physical-device id
  that a third-party SDK may use for billing. `ANDROID_ID`
  (`Settings.Secure.ANDROID_ID`) is scoped per signing key + user and
  its use for identifying users is discouraged; hardware ids (IMEI,
  serial) are permission-gated and unavailable to modern apps. So the
  SDK generates a random UUID on first use and stores it in the app's
  own private `SharedPreferences`.
- **SharedPreferences is wiped on uninstall**, so by default a
  reinstall produces a *fresh* UUID (a new `deviceId`).
- A host app can opt into **Android Auto Backup**
  (`android:allowBackup="true"` in its manifest) to persist the prefs
  file across uninstall/reinstall, restoring the same `deviceId` on
  reinstall. Without that, "one device per install" is the actual
  semantics on Android, and the server-side reconciliation (below) is
  what keeps a brief reinstall from allocating an extra permanent seat.

The value is a non-secret random UUID (not the token), so plain
`SharedPreferences` (mode `MODE_PRIVATE`) is adequate; the
Keystore-backed crypto used for bundle staging would add no defense in
depth here. The id is read through an in-process cache so repeat
lookups don't touch disk.

## Reinstall & the server-side seat contract

Because the Android `deviceId` may rotate on a bare reinstall (unless
Auto Backup is on), the backend owns the guarantee that a short
"used → uninstalled → reinstalled" cycle does not cost a permanent
extra seat. The `/app-on-device` endpoint at `backend.thestage.ai`
must:

1. **Upsert by `(userApiToken, deviceId)`.** A POST whose pair already
   exists must update the existing seat's `last_seen` and return
   `canUsePackage` — it must **never** increment the billable device
   count for a duplicate pair.
2. **Reactivate within a window.** If a `deviceId` reappears after its
   seat was released/deleted, reuse the existing seat (no new charge)
   within a configurable reactivation window (e.g. 30 days), so a brief
   uninstall/reinstall gap does not allocate a fresh seat.
3. **Be idempotent to repeated POSTs.** Each fresh app launch
   re-validates online and POSTs `(userApiToken, deviceId)` again; the
   server must treat a repeat as the same upsert, not a new activation.

## Online validation & TLS (SDK side)

Source: `security/TokenValidator.kt`.

- The token is validated online on first use, and the device must be
  reachable then — there is **no offline grace window**. A transport
  failure or HTTP 5xx is a hard init failure; a hard backend rejection
  (HTTP 4xx / `isSuccess=false`) also fails immediately, and the SDK
  drains any queued offline initializations left by older builds to
  avoid spinning on a dead token.
- A per-process in-memory cache skips re-validation for a token already
  validated in this process, but a fresh app launch always re-validates
  online (no cross-launch skip).
- TLS is pinned to a fixed root CA set (Amazon Root CA 1–4 +
  Starfield Services Root G2) via a custom `X509TrustManager`,
  so the validation endpoint cannot be MITM'd with an unrelated CA.

## Device integrity (release builds)

On a **release** build (the embedding app is not debuggable) the SDK
runs a best-effort environment check before it loads any engine and
**refuses to load** on an obviously compromised device — rooted,
running under an emulator, an instrumentation/injection framework
(e.g. Frida/Xposed), or with a debugger attached. It is a deterrence
layer that complements — never replaces — the encrypted `.qlpd` bundle
handling; the check never reveals which probe fired.

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
| Reinstall (Auto Backup **on**) | unchanged `deviceId` | 1 |
| Reinstall (Auto Backup **off**) | new `deviceId` | server reuses the old seat within the reactivation window; otherwise a new seat |
| Two different developers' apps, one device | different tokens | 2 |
| App relaunch after a prior online validation | unchanged | 1 (re-validates online each launch) |

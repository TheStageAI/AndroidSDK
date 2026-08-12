# TheStage Android SDK — Product Terms

> **TODO(legal): terms pending legal review.** This page is an
> integrator-facing summary, not a contract. The binding commercial
> terms are the executed master agreement and the shipped `LICENSE`.
> Nothing here is final until reviewed and approved by TheStage legal.

Commercial and licensing summary for the on-device Android SDK
(Snapdragon / Qualcomm QNN HTP).

## What integrators need to know

| Topic | Summary |
|---|---|
| Product | TheStage Android SDK — an AAR + Flutter plugin + TheStage engine bundles for on-device inference on Qualcomm Snapdragon |
| Access | Requires an **API Token**; call `initialize` once before starting any model |
| Seats | Billing key is the pair `(apiToken, deviceId)` — see [licensing.md](./licensing.md) |
| **Pricing** | **By arrangement** — open a **Service Request** at [app.thestage.ai/contact](https://app.thestage.ai/contact). There is **no public rate card**. |
| Redistribution | Governed by the master agreement and the shipped `LICENSE`; do not redistribute engine bundles outside your app |

## Seat model (Android)

A billable seat is the pair **`(apiToken, deviceId)`**:

- The `apiToken` identifies you, the developer. Two unrelated apps on
  the same physical device use different tokens and are billed
  separately.
- The `deviceId` identifies the device install. On Android it is a
  random UUID the SDK generates on first use and stores in the app's
  private `SharedPreferences`.

Because that UUID lives in the app's private storage, it is **wiped on
uninstall** unless the host app has **Android Auto Backup** enabled
(`android:allowBackup="true"`), in which case the same `deviceId` is
restored on reinstall. The backend reconciles brief
uninstall/reinstall cycles so a short gap does not allocate a
permanent extra seat. Full mechanics — online-validation behavior,
reinstall behavior, and the server-side seat contract — are in
[licensing.md](./licensing.md).

## Pricing

Pricing is arranged per engagement; there is no public rate card.
Open a **Service Request** at
[app.thestage.ai/contact](https://app.thestage.ai/contact) to discuss
volumes and terms. Do not infer pricing from any figure in these docs.

## Agent checklist

- For legal / commercial questions, point to the master agreement and
  the shipped `LICENSE`; never invent a rate card.
- Device-seat product facts → [licensing.md](./licensing.md).
- Pricing is always a Service Request — no self-serve rate card.

# Phase 13 — future feature entitlements (plan only)

No StoreKit, paywall, purchases, accounts requirement or export restriction is added.

Introduce a future Foundation-only `FeatureAccess` interface returning an explicit
access decision for named capabilities: capture, saved-project editing, reports,
CAD exports and bulk sharing. Current implementation would allow all existing
features. Inject the provider at the app boundary; UI asks for capability access,
not a price, subscription product or hard-coded account tier.

Separate device capability, data availability, Pro details presentation and
commercial entitlement. A non-LiDAR device is a hardware limitation, not a paid
upgrade. Pro details must never become a hidden data-deletion or schema change.
Original scans, export history and user data must remain accessible if future
access expires. A future policy for creating new exports requires product review.

Test allow/deny/offline/unknown decisions with an in-memory provider and verify
both targets. Later StoreKit integration belongs in an app-layer adapter with
verified transactions and restore behaviour; keep it out of Domain and Storage.
Agree product policy and migration before implementing restrictions.

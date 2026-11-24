# Phase 12 — before/after comparison (plan only)

Preserve both captures as independent immutable source references in a project.
Add a future comparison sidecar with baseline reference, follow-up reference,
explicit rigid transform, checkpoint observations and reviewer decisions. Do not
change existing scan packages. Agree the sidecar schema before implementation.

First scope: one level, plan overlay and side-by-side photos with dated notes.
The user chooses corresponding corners; a third independent checkpoint checks
alignment. Show residuals, tracking interruptions, unmatched/occluded areas and
unverified status. Refuse automatic geometric differences until alignment is
reviewed. An apparent difference can be capture noise or occlusion, not renovation.

Later scope: user-reviewed wall/opening/equipment matches and documented quantity
deltas. No inferred hidden pipe changes, heat-load results or automatic compliance.
Keep manually approved matches separate from candidate matches and preserve IDs.

Tests: asymmetric rigid transforms, reflected transforms rejected, missing source,
interruption, checkpoint residuals, correspondence conflicts, repeatable fixtures,
round-trip review decisions and localized reports. Device validation pending.
No comparison implementation or new package schema is included now.

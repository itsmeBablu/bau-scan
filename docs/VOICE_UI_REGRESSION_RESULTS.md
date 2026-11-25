# Local voice/UI regression work

Branch: codex/voice-ui-regression-fix, based on f19789a. No push or installation is
part of this request. The original incremental-saving work remains in place.

- Step 0: 907cd58, audit of 25 changed files against 3f0e9a5, +80/-0 lines.
- Step 1: a61c43b, recorder event policy, state machine, diagnostics and tests,
  6 files, +142/-12 lines. Five initial policy/localization tests passed.
- Step 2: 8ae69c0, close/discard escape, timeout, single-scan selection, compact
  held-recording waveform/slide cancel, player and Technik menus, 7 files,
  +150/-52 lines. iPhone-target compilation passed.
- Step 3: local project cards, five tabs, optional details/parties/defaults and
  opt-in project-details ZIP export, 12 files, +259/-38 lines.
- Final validation: 10 focused tests passed, including bilingual coverage and
  private-details export opt-in. The two final layout checks also passed.
  iPhone-target compilation and final Mac-target build passed. Empty-state
  layout was rendered and inspected. Microphone/AR device checks remain unrun.

## Verified findings

The baseline has no NoteAudioRecorder. Its supposed card UI is actually a set of
lists, so the new cards are an implementation, not a faithful file restoration.
The introduced recorder indiscriminately stopped on all notifications, including
its own category changes. The new pure policy ignores category/configuration
changes, interruption-ended and output-only changes. Route loss is ignored for
500 ms following activation. Only began interruptions, input loss, media resets
and background transitions cause system stops. Short clips report a message.
The log category is voice. Settings shows permission and last stop reason.
The audio category is retained if it already supports recording. The camera/AR
session is not restarted. Physical microphone/camera behavior remains unverified.

Close is always available in notes management, with loss confirmation; a stuck
preparation has a 15-second watchdog and UI operations have a 30-second timeout.
A timed-out worker may still complete its durable write; recovery copies are kept.
The live camera uses the compact held microphone, rather than this list screen.

Saved and live Technik view visibility is controlled by the top-right ellipsis:
room surfaces, ceiling, photos and voice notes. Saved audio uses a half-height
player with scrubber. Camera/project notes retain their existing data formats.

## Explicit stop boundary before Step 4

The supplied instruction says: “Stop and report if a step needs more than about
300 lines.” Safe per-scan deletion cannot reuse ProjectPrivacyStore.delete as-is:
that operation deletes an entire project's note directory and purges its trash.
TechnicalRoomLibraryStore.delete only moves the package; it does not transactionally
update notes, designs, project references or draft-session media.

A correct per-scan operation needs a journaled transaction across package files,
filtered project-note files, dependent designs, the project index, and retained
session media; rollback and launch recovery; cross-project dependency protection;
plus card context menus, multi-selection UI and injected-failure tests. This is
estimated above 300 lines. No partial destructive implementation was introduced.

Next reviewable implementation: preflight the dependency set; stage a filtered
notes directory; journal original/trash/replacement paths; rename on each owning
volume; commit the catalogue; retain recoverable trash; on launch reconcile the
journal against the committed index. Test failure at every move/commit boundary
before enabling the card actions.

Deleting an internal room from a House is also not a safe standalone file deletion:
house.json, structure.json, structure-apple.json, room folders, hosted openings,
photos, radiators, notes and existing designs can all depend on it. No safe room
removal/rebuild transaction currently exists; do not delete its folder alone.

Step 4 is pending. Step 5's new aim metadata and microphone/aim-line renderers in
2D/3D/Studio are pending at this stop boundary. Existing photo markers are kept.
Step 6's draft/background saving is already implemented on the parent branch;
it is not reverted. Its live-camera/device tests remain pending.

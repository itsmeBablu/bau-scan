# Ordered work queue — 2026-11-26

1. Complete current camera/voice/pin fixes, all local checks, separate Test-app install and device validation.
2. Merge the validated work to local main, then branch `codex/robust-architecture` and follow the user's attached phases 0–10. Preserve behaviour and file formats. One small commit per step, gates between phases; no new app dependencies. Do not claim remote CI or device performance without evidence. Unrelated `.agents` edits are user changes and must remain untouched.
3. At the end, implement the requested WhatsApp-style voice control: one row, elapsed seconds, in-place play/pause and seek; hold menu for re-record/delete/record. Apply to capture and saved notes as appropriate. Preserve durable audio/outbox semantics.

Architecture source: `/Users/babureddy/.codex/attachments/baa96658-6b66-4e44-8286-6583f89ebeae/Pasted text.txt`.
Current branch: `codex/camera-performance-and-markers`.
4. Final naming/list actions requested afterward: before starting House or Technik capture, ask for its saved name. Saved items expose Rename and Delete in their hold/context menu. Preserve UUID-based storage paths and durable deletion/recovery semantics.

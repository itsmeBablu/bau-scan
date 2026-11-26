# Bugs found during camera fixes and architecture preflight

- Session-store path validation could loop forever at `/` when Foundation returned a canonical `/private/var` URL and the configured root used `/var`. Fixed with canonical containment, retained symlink rejection and a bounded ancestor walk. The full Mac suite reproduced the loop in `ScanSessionIntegrationTests`; focused simulator recovery tests had not exposed it.
- Native export snapshot relative paths used string offsets across those same aliases, producing truncated paths. Fixed with canonical path components; the existing byte-preservation test covers it.
- Mesh exports appended legacy corner patches after generating resolved joined wall solids. Removed those duplicate patches; the existing closed-wall count/volume test covers it.
- Technical survey handoff export referenced an absent bundled schema. Added the extension schema; existing handoff decoding and core-schema validation remain in place.
- Furniture classification matched `desk` inside `desktop` before checking computer categories. Prioritized the existing computer check; covered by the existing office collection test.
- Full-suite test issues: source localization reads blocked on Desktop access; ZIP inspection assumed local sizes in streaming headers; scene dimension lookup assumed the first root child was a room; IFC wall-count oracle ignored the exporter's canonical per-storey input. Corrected the test harnesses without weakening the corresponding contracts.

## Still to investigate in the architecture phases

- Wall graph topology can depend on source room/wall ordering. IFC deliberately canonicalizes its per-storey input; compare the other consumers before changing graph behaviour.
- Physical camera/microphone interaction, sustained large-house capture memory, thermal dimming and AR marker occlusion remain device checks. Unit tests and compilation do not prove them.

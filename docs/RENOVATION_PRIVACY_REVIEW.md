# Privacy implementation and release review

New users stay local unless they explicitly enable iCloud. An existing populated
cloud library is detected to preserve access. Startup and cloud selection no longer
automatically migrate local packages; the project inventory references both roots.
Technical-room capture keeps its independent local library. Explicit exports and
sharing remain user actions. Turning cloud off does not delete cloud content.

AI is optional and off by default. Every enabling control now presents consent;
each upload still requires selecting photos and confirming the service destination.
Turning AI off prevents new submissions and existing cancellation handling stops
an active Google job. An already transmitted request cannot be recalled. Google
sign-in is optional; account identity and selected images reach the configured
service. Depth remains local in the existing image-recognition request path.
API credentials stay on the backend.

Project deletion preflights generated paths in connected, known libraries. It
does not recurse over arbitrary user paths. It protects source scans referenced by
another project's design. Index and generated project exports are separate from
original formats. Deleting a package also deletes its contained photos. A failed
operation reports possible partial deletion and retains catalogue references for
review; this is not a transactional secure-erasure guarantee. Unconnected libraries
block the deletion. Files shared outside the app, historical export folders,
technical-library trash, OS/iCloud backups and backend/provider data are outside
this action and are explicitly identified in the UI.

## Manifest

Added `RoomScanner/Resources/PrivacyInfo.xcprivacy` with no tracking and required
reason entries for app preferences (CA92.1) and file metadata within the app's
storage (C617.1). These categories match source use. No disk-space API was found in
the audited capture path, so no unused disk-space reason is added.

References checked during implementation:

- [Apple TN3183: required reason API entries](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest)
- [Apple: required reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [Apple: data collection details](https://developer.apple.com/documentation/technotes/tn3184-adding-data-collection-details-to-your-privacy-manifest)

**Release gate:** the data-collection declarations and App Store privacy answers
still need review against the deployed backend's actual logging, retention,
subprocessors and Google/Sparkle SDK manifests. The required-reason manifest is
not a claim that no data is collected, that App Store validation passed, or that
legal obligations have been satisfied. Archive with Xcode, inspect the generated
privacy report and confirm the resource is bundled in both targets. These checks
are unrun on Windows.

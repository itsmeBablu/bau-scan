# Security/privacy — local review checkpoint

No credentials, private photos or audio are included in these commits. No network
requests to the user's AI deployment, signing or release services were performed.
No secret environment files were read. All Git changes remain local.

Reviewed the Google service authentication/input/rate/cache paths. It checks OAuth
audience/issuer, verified email and allowlist; bounds uploads; isolates recognition
cache by identity/model/image and limits concurrent jobs. Existing 13 service tests
pass locally. This is prototype coverage, not a production penetration test;
network cancellation, multi-worker limits, deployment configuration and external
processing disclosures still need integration review. No new audio upload exists.

Voice audio is locally recorded only after a user action and first-use explanation.
Microphone usage descriptions are EN/DE. No speech permission or transcription
service is enabled. Local recovery copies live in app-specific Application Support;
they are separate from scans and retained after failed delivery. User audio storage
and selected export are not a claim of full anonymization.

Photo exports optionally re-encode derived copies without source EXIF/GPS metadata.
Native backups preserve originals and cannot be combined with metadata removal.
Names, visible content and scan-relative camera poses can still be sensitive.

Added NSPrivacyAccessedAPICategoryDiskSpace/E174.1 for observable recording disk-space
checks, based on [Apple required-reason documentation](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons).
Capacity values are not sent off-device. This is not App Store privacy approval;
the complete app/SDK collection declarations still require a release review.

Strengthened listed-file manifest checks and localization JSON duplicate detection.
Three Node duplicate-key regression tests pass. Swift security/storage tests are
UNRUN. Remaining: Keychain/SDK runtime behavior, security-scoped access throughout
imports/exports, cloud protection, consent journeys and signed-build validation.

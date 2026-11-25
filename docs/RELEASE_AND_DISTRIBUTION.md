# Release/distribution — Phase 7 local checkpoint

No remote workflow, release, appcast or signing operation was performed. No Mac
or iPhone artifact exists for these commits. Apple build/test status is BLOCKED on
this Windows host. Workflow source is prepared, not proven to execute successfully.

## Prepared workflows

- tests.yml: existing manual/PR full RoomScanner and RoomScannerMac schemes plus
  service/localization checks; adds the three Node duplicate-JSON-key regressions.
- ios-unsigned.yml: existing manual physical-iPhone Release-Local build; keeps the
  xcode-27 runner and no signing, standard Payload IPA and ZIP integrity check.
  Adds commit/version/configuration/actual architecture metadata, checksum and
  installation limitations to the artifact. XcodeGen installation is idempotent.
- macos-unsigned.yml: new manual-only macos-26 workflow; generates with XcodeGen,
  requests universal arm64/x86_64 Release and verifies both reported architectures,
  packages ZIP/DMG with integrity checks, metadata, checksums and installation
  notes. Both architecture builds and dependencies remain UNVERIFIED.

All use read-only contents permission and ephemeral checkout credentials; Mac
artifacts/logs retain three days. Existing iOS retention remains seven days.
No push-triggered automatic build or public-release step was added.

Runner references checked on 2026-11-25 against the official
[runner images inventory](https://github.com/actions/runner-images/blob/main/README.md)
and [macOS 26 software list](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md).
The toolchain actually used is logged at execution time; runner availability is
not a successful application build. No runner label was guessed or silently
downgraded. Current minimums remain iOS 18 and macOS 15.

## Running later, when remote work is authorized

After pushing the reviewed branch to the user's repository, open Actions, choose
the test workflow, Run workflow, select that branch and run it. Inspect both
complete schemes and download test logs/.xcresult before interpreting the build
workflows as usable apps. Then choose the manual unsigned iPhone or Mac workflow,
select the same branch/SHA and run. Download only a successful job's artifact.
Unzip the outer artifact; the IPA, Mac ZIP/DMG, build-info and SHA256SUMS are inside.
On Windows compare Get-FileHash -Algorithm SHA256 against the included checksum.
No actual run URL or downloadable artifact is available yet.

## Signing and installation limits

Unsigned IPA is not directly installable on iPhone. It needs local re-signing;
free-account entitlement, bundle-ID changes, Google login, trust/Developer Mode
and refresh behavior need device validation. The Release-Local build uses the
existing local-storage configuration; do not add Apple passwords or private keys
to source control. Windows does not run Xcode.

Mac builds are unsigned and not notarized. Gatekeeper, signed installation,
Intel/Apple Silicon execution, upgrades, entitlements and libraries are unverified.
No automatic security bypass is provided. Production distribution requires an
appropriate Developer ID/signing/notarization process and explicit release approval.
Sparkle configuration/signature checks were inspected but not changed; appcast
publication and update delivery remain unauthorized and unverified.

## Remaining release gates

Both full Apple schemes; generated sample archives and per-format reader checks;
real light/dark EN/DE screenshots; physical capture/audio/alignment checks;
complete backup/import/restore; Google consent/login/runtime checks; large project
profiling; signing/notarization and upgrade tests. No production readiness,
engineering accuracy or DIN compliance is claimed.

# Separate iPhone test installation

The iOS target supports a local bundle identifier, display name and signing team
without committing those choices or losing them when XcodeGen regenerates the project.

1. Copy `Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig`.
2. Set a unique `DWALK_IOS_BUNDLE_IDENTIFIER`, a recognizable
   `DWALK_IOS_DISPLAY_NAME`, and your `DEVELOPMENT_TEAM[sdk=iphone*]`.
3. Run `xcodegen generate`, open `RoomScanner.xcodeproj`, select the `RoomScanner`
   scheme and the connected iPhone, then Run. Keep automatic signing enabled.

Different bundle identifiers install as separate apps with separate local data.
Later builds with the same test identifier update that test app. Keep the original
app installed; export/import scan packages when you want to copy scans into the new
one. The iOS target currently uses local-only storage and no iCloud entitlement.

The ignored local file is included by the iOS configuration and survives pulls and
project regeneration. Without it, the existing `localtest` identifier and
`dWalkScan` display name remain the defaults. macOS identity is unchanged.

Google sign-in requires an iOS OAuth client registered for the actual test bundle
identifier. Use a matching client in the ignored `GoogleAI.local.xcconfig` before
testing sign-in; the bundled client for a different identifier is not sufficient.
Camera, microphone and local scanning do not require Google sign-in.

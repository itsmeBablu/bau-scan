# Native navigation refinement

The iPhone/iPad root uses five native SwiftUI tabs: House, Technik, Capture, Profile and Settings. These are destinations, not camera action buttons. Capture opens a chooser for a continuous House walkthrough, a single Room or a Technik Room. Saving routes to the appropriate library/detail after dismissing capture. Studio remains in each saved scan's Options menu.

House contains House and Room packages; Technik contains independent technical surveys. Both libraries support native search. Filtered House/Room deletion resolves indices against the filtered records. Technical library refresh tokens reload saved/imported records after modal workflows. Unsupported devices cannot start scanning through either new entry point.

Profile contains local name and organisation preferences only; it does not imply an authenticated account or automatically populate verification/export author fields. Google account and AI connection remain in Settings. The embedded Settings screen has a large navigation title and no modal Close button.

Visual changes include semantic foreground/background colours, consistent 64-point rounded thumbnails, neutral secondary row menus, a system blue accent and adaptive materials with restrained separator borders. The old yellow gradient outlines and yellow panel wash are removed from shared material modifiers. Scan evidence colours and Studio materials are unchanged.

macOS retains its sidebar and native menus; no iPhone tab bar is added to the Mac app.

The interface follows native navigation conventions and takes hierarchy cues from Apple Music. It is not an exact Apple Music replica or Apple certification. Actual tab/bar appearance follows the installed iOS version. Physical-device interaction and scanning checks remain pending.

The three engineering review findings from commit 505406d are outside this UI refinement and remain open.

Validation: 245 macOS regression tests and 243 final iOS simulator tests passed. The new hosted UI test verifies all five native tab labels and renders the layout for visual inspection. Final macOS and signed generic iPhone builds passed. Simulator capture remains unavailable as expected without LiDAR hardware.

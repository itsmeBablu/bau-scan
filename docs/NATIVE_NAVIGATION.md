# Native navigation refinement

The iPhone/iPad root uses five native SwiftUI tabs: House, Technik, Capture, Studio and Profile. These are destinations, not camera action buttons. Capture opens a chooser for a continuous House walkthrough, a single Room or a Technik Room. Saving routes to the appropriate library/detail after dismissing capture. Studio is also available from each saved scan's Options menu.

House contains House and Room packages; Technik contains independent technical surveys. Both libraries support native search. Filtered House/Room deletion resolves indices against the filtered records. Technical library refresh tokens reload saved/imported records after modal workflows. Unsupported devices cannot start scanning through either new entry point.

Profile combines local name/organisation preferences, Google sign-in/account details, AI connections and app settings. Local workspace details do not imply authentication or automatically populate verification/export author fields. Google sign-in requires configured OAuth client IDs and callback scheme. The combined page uses a large native navigation title and no modal Close button.

Visual changes include semantic foreground/background colours, consistent 64-point rounded thumbnails, neutral secondary row menus, a system blue accent and adaptive materials with restrained separator borders. The old yellow gradient outlines and yellow panel wash are removed from shared material modifiers. Scan evidence colours and Studio materials are unchanged.

macOS retains its sidebar and native menus; no iPhone tab bar is added to the Mac app.

The interface follows native navigation conventions and takes hierarchy cues from Apple Music. It is not an exact Apple Music replica or Apple certification. Actual tab/bar appearance follows the installed iOS version. Physical-device interaction and scanning checks remain pending.

The engineering review findings from commit 505406d are addressed in the subsequent refinement: additions switch reference views to Proposed, selected search results are retained beyond the list cap, and annotation-only edits do not rebuild the scene. Engineering record lookup now uses a nonserialized index rebuilt on decoding and mutations.

Validation: the latest combined refinement passed 262 macOS and 260 iOS simulator tests, including all five native tab labels. Portrait and landscape Studio layouts were rechecked after the final dock adjustment, and a signed iPhone build passed. Native/rendered layouts were inspected. Physical-device camera and LiDAR validation remains pending.

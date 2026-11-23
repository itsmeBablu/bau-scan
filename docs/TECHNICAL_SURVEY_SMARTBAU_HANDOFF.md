# Technical survey editing and photo review

## Export and import

Open a saved technical room and choose **Export → Editable technical survey JSON**.
Export **USDZ** from the same survey if a reference file is needed.
In Smart-Bau, drop the survey JSON into the existing scan import dialog.
The matching USDZ is optional. Its survey identity is checked when supplied.
The current pairing check uses the survey ID, so two different revisions of the same
survey still require the user's review. Raw USDZ triangles are not retained in the
Smart-Bau document by this importer.

The standalone survey export contains effective edited pipe routes, duct edits,
equipment, fittings, endpoint connections, original pipe observations, calibration
information and accepted detections with their session-to-room transform.
Existing package JSON remains compatible.

Smart-Bau creates native equipment instances and native pipe/duct segments.
Routes retain vertical rise and start elevation. Equipment centres convert to base
elevation. Coordinates map from room metres to layout millimetres as
X = 1000*x, Y = 1000*z, elevation = 1000*y. Yaw converts to negative degrees.
Known boiler, heat-pump and electrical-panel categories use existing catalog families.
Other equipment currently uses generic components. Fittings use linked survey points,
and their exact dimensions and engineering geometry require further work.
Unknown pipe media and duct systems import as unassigned.

A non-unity scale calibration currently blocks import with an explicit message.
Calibrated geometry must be implemented consistently across observations, entered
equipment sizes and reference geometry before this restriction can be removed.
Repeated import of the same identities is rejected by the existing import command.
Updating an existing imported survey is future work.

## Photo review

Saved survey photos have matching numbers in the 3D view and photo strip.
Select a number to display its image below the model. Open it full screen to inspect
the image with zoom controls. Yellow camera frustums show the saved camera direction
and image extent from the recorded pose and intrinsics.

## Google account

The connection view shows account identity and connection progress.
Service configuration is available in a disclosure group.
Google OAuth setup is required in the build for sign-in.

## Verification

The Smart-Bau regression selection covers survey import, vertical pipes, ducts,
equipment-port connections, USDZ identity matching and existing house imports.
The selected 77 tests passed during implementation.
The latest whole-web type-check is blocked by concurrent edits outside this feature.
Both Apple schemes still require a Mac build and test run.

Device validation pending on iPhone and iPad:

- Verify House radiator setting enabled and disabled across new capture sessions.
- Inspect numbered photo markers, camera directions, inline images and full-screen images.
- Test Google sign-in, restoration, cancellation and sign-out with configured OAuth.
- Export a real survey and check equipment positions, riser elevations and route lengths
  after importing into Smart-Bau, saving and reopening.

Full Smart-Bau catalog reuse inside iOS Studio, a trained radiator classifier,
complete fitting topology, revision updates and raw USDZ overlay persistence remain
future work. Radiator detection currently produces geometric candidates for review.

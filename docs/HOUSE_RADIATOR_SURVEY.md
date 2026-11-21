# House radiator close-up survey

During a House walkthrough, choose **Capture radiator**, mark the three front corners and adjacent wall, walk around its visible sides, then choose **Save radiator and continue House**. Finish House only after completing the walkthrough. This is assisted identification, not automatic radiator classification. The observer reads the existing House AR session without replacing its delegate, running a second session, changing its configuration or pausing the House camera. A missing-depth status is shown rather than pretending capture succeeded. Actual availability of RoomPlan camera depth must be verified on device.

Observations from this uninterrupted session retain House coordinates and are associated with the final room/wall. The saved House 3D/AR viewer includes a radiator envelope when Objects is enabled. Unknown thickness is shown as a flat surface rather than an invented depth. Room/wall associations beyond one metre are explicitly marked approximate. Independent saved-House close-up scans retain their separate coordinate frame and are not falsely placed in the House model. These envelopes are app viewer geometry; Apple's original RoomPlan USDZ remains unchanged.

Open a saved House, choose Options → Radiators, select the room and optional wall reference, then Scan radiator on a LiDAR-equipped iPhone/iPad. This is a separate AR session; continuous House capture and Technical Room capture are unchanged.

Mark the radiator body's lower-left, lower-right and upper-left front corners, then a point on the adjacent parallel finished wall. Exclude valves, pipes and brackets. Move slowly around visible front, side and top surfaces. Finish and review before saving.

Width/height come from marked scene-depth points. Wall-to-front distance comes from the marked front and adjacent wall. Body depth requires a rear-facing surface supported by at least 20 samples from two viewpoints. Wall Abstand means finished wall to the radiator body's back; it is wall-to-front minus observed body depth. Hidden rear surfaces remain unknown. Reflective surfaces, depth noise, incorrect corner selection and occlusion affect these estimates; no millimetre accuracy is certified.

There is no generic German/DIN gap applied by default. The optional 30/50 mm examples are explicitly assumed settings for KERMI's long wall console, not universal mounting requirements. Check the actual radiator and bracket instructions: https://www.youtube.com/watch?v=zxw3laHBoAs . A supported rear observation takes priority. Derived depth also remains labelled as assumed when a mounting assumption supplies the gap.

Entered tape, laser or manufacturer dimensions retain that source; manufacturer values require a reference. Original observations remain available. All numeric survey dimensions and JSON exports use metres. The preview is a survey envelope or observed surface samples, not a detailed engineering model or a registered placement in the House coordinate frame.

The optional `radiators.json` sidecar travels with the `.housescan` package. House rename/recalculation preserves it; duplicate import remaps its House ID. Existing Houses without the sidecar still open normally. Capture requires device validation; simulator tests validate geometry and storage, not physical measurement accuracy.

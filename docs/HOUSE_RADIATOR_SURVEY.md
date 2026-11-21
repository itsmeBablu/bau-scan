# House radiator close-up survey

Open a saved House, choose Options → Radiators, select the room and optional wall reference, then Scan radiator on a LiDAR-equipped iPhone/iPad. This is a separate AR session; continuous House capture and Technical Room capture are unchanged.

Mark the radiator body's lower-left, lower-right and upper-left front corners, then a point on the adjacent parallel finished wall. Exclude valves, pipes and brackets. Move slowly around visible front, side and top surfaces. Finish and review before saving.

Width/height come from marked scene-depth points. Wall-to-front distance comes from the marked front and adjacent wall. Body depth requires a rear-facing surface supported by at least 20 samples from two viewpoints. Wall Abstand means finished wall to the radiator body's back; it is wall-to-front minus observed body depth. Hidden rear surfaces remain unknown. Reflective surfaces, depth noise, incorrect corner selection and occlusion affect these estimates; no millimetre accuracy is certified.

There is no generic German/DIN gap applied by default. The optional 30/50 mm examples are explicitly assumed settings for KERMI's long wall console, not universal mounting requirements. Check the actual radiator and bracket instructions: https://www.youtube.com/watch?v=zxw3laHBoAs . A supported rear observation takes priority. Derived depth also remains labelled as assumed when a mounting assumption supplies the gap.

Entered tape, laser or manufacturer dimensions retain that source; manufacturer values require a reference. Original observations remain available. All numeric survey dimensions and JSON exports use metres. The preview is a survey envelope or observed surface samples, not a detailed engineering model or a registered placement in the House coordinate frame.

The optional `radiators.json` sidecar travels with the `.housescan` package. House rename/recalculation preserves it; duplicate import remaps its House ID. Existing Houses without the sidecar still open normally. Capture requires device validation; simulator tests validate geometry and storage, not physical measurement accuracy.

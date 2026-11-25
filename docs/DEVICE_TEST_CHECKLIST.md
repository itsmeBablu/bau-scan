# LiDAR device checks — pending

No live LiDAR capture validation is claimed for this branch. Installing or
launching the app is not equivalent to validating these scenarios.

- [ ] Capture three adjacent House rooms with one shared ARSession; confirm room
  saves, RoomPlan restart, common coordinates, coaching and Finish behavior.
- [ ] Force-quit during every room/segment/media write and finalization; recover
  saved data, retry Finish, and confirm no completed package is overwritten.
- [ ] Large-room snapshot triggers: time, geometry growth, encoded-size growth,
  memory warning, pause, interruption and background flush expiry.
- [ ] Profile encoded bytes, snapshot milliseconds, resident memory, thermal state,
  peak finish memory, main-thread stalls and disk capacity; tune conservative limits.
- [ ] Resume via world-map relocalization behind a flag; failed alignment must
  prevent automatic merging of new rooms with recovered geometry.
- [ ] Technik new/changed/removed mesh anchors survive delta recovery without
  repeatedly serializing the full growing mesh; verify final package compaction.
- [ ] Photos and stopped voice clips survive force-quit immediately after capture;
  verify room, level, pose, orientation, timestamp and old-clip replacement safety.
- [ ] Record and release the mic while House and Technik cameras remain live;
  inspect audio category transitions, interruptions, meter/redraw rate and AR FPS.
- [ ] Verify pins target the intended surface/object in both scan types.
- [ ] Recover / Discard names the draft, preserves completed scans and unrelated
  drafts, and remains correct after interruptions at every storage crash point.
- [ ] Open existing roomscan, housescan and technicalroom packages, plus designs.

The Step 1 store has local injected-failure tests. Capture integration, launch
recovery UI, trigger counters and the checks above remain unimplemented/unrun
until the Step 2 lifecycle-validation boundary is resolved.

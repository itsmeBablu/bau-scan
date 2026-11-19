# Technical Room interchange v1

This is an independent UTF-8 JSON document. It references an existing shell by
shellID and does not alter .roomscan or .housescan packages. IDs are UUIDs stored
in the model and reused on re-export. Export requires the shell package to remain
available separately. Photos are references rather than embedded image bytes.

Coordinates are right-handed, Y up, metres. Point objects use x/y/z.
Equipment size.x is width, size.y height, size.z depth. The origin is (0,0,0)
in room space. shellToRoom supplies translation and orthonormal basis columns:
roomPoint = translation + shellX*xAxis + shellY*yAxis + shellZ*zAxis.
Shell input is RoomPlan's 3D frame, not FloorPlan's flattened (x,-z) coordinates.
northAzimuthDeg is optional, clockwise from room -Z toward +X.

Pipe surface normals point from the observed surface toward the camera. For a
hit on the outside of a pipe or its insulation, centreline = hit - normal *
(outerDiameterMm/2 + insulationThicknessMm)/1000. Normals are normalized.
When centerlineStandoff is supplied, the hit is on a supporting wall or ceiling:
centreline = hit + normal * centerlineStandoff. Re-export recomputes the
centreline, lengths and elevations. Curves are represented by straight polyline
segments. Hidden geometry is never inferred as measured.

Every engineering value uses value/unit/source/method/accuracyMm. Identity,
relationship IDs, collections and schema metadata are structural fields.
Transform basis vectors are unitless although the transform wrapper uses m for
its translation. Derived quantities have estimated source and documented method.
Accuracy is null unless a validation basis exists. DN is a designation such as
DN20, not an outer diameter. Unknown DN totals use the key unspecified.

## Bau conversion

For room coordinates (x,y,z):
layout xMm = 1000*x; layout yMm = 1000*z; elevationMm = 1000*y.
Elevation is relative to the chosen Bau level.
Equipment base elevation = 1000*(center.y - size.y/2).
Width/depth/height = 1000*(size.x,size.z,size.y).

Room positive yaw theta is a right-handed rotation around +Y:
x' = cos(theta)*x + sin(theta)*z
z' = -sin(theta)*x + cos(theta)*z.
Bau's plan rotation uses x' = cos(phi)*x - sin(phi)*y,
y' = sin(phi)*x + cos(phi)*y. Therefore rotationDeg = -theta*180/pi.

Example: center (1.2,1.0,2.4), size (0.6,1.6,0.5), yaw +pi/2:
xMm=1200, yMm=2400, base elevationMm=200,
widthMm=600, depthMm=500, heightMm=1600, rotationDeg=-90.
A local port at (0.3,0,0), local direction (+1,0,0), has room position
(1.2,1.0,2.1) and room direction (0,0,-1).
Bau local connector offsets are relXmm=300, relYmm=0, relZmm=800;
local connector dir=[1,0,0]. Its world location is (1200,2100,1000)
in Bau worldXmm/worldYmm/worldZmm naming.

Stored ports use room-space positions/directions. To generate local connector
offsets, subtract the equipment center, apply inverse yaw, and add half equipment
height to the local Y coordinate before mapping to relZmm.
Bau's native pipes need independent endpoint elevations for vertical risers.
This phase does not modify Bau or silently flatten those runs.

## Validation

Schema: RoomScanner/Resources/technical-room-v1.schema.json (draft 2020-12).
The dependency-free Swift validator implements only the keywords used in this
schema. Export validates structure, positive pipe diameter, nonzero normals,
unique IDs, and references. No AR or UI is present in T1.
JSON computed values are regenerated rather than trusted on decoding.

Mac/simulator builds and tests have not run. Device validation pending for
every capture-derived input. Never claim sub-centimetre accuracy.
On device, compare five pipe lengths and width/depth/height of three equipment
items against tape measurements. Repeat three times, check a third alignment
checkpoint, and repeat after interruption/relocalisation. Record absolute and
relative errors and drift, preserving null accuracy until validated.

Pending future work includes AR acquisition, persisted technical documents,
annotation UX, and Bau importer implementation. Persisting this separate
document does not authorize changes to the shell package formats.

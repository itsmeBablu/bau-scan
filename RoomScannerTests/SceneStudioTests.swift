import XCTest
import SceneKit
import simd
import ModelIO
#if os(iOS)
import SwiftUI
import UIKit
#endif
@testable import RoomScanner

final class SceneStudioTests: XCTestCase {
    @MainActor func testLegacySingleRoomOffsetDoorsRenderOnlyOneDoorway() throws {
        var room = seed().shell.allRooms[0]; room.transform = .identity
        let door = Opening(id: UUID(),kind: .door,wallID: nil,center: .init(x: 1,y: 1),width: 0.9,height: 2,sillHeight: 0,angle: 0,confidence: .high)
        var duplicate = door; duplicate.id = UUID(); duplicate.center = .init(x: 1.06,y: 1.14); duplicate.width = 0.97; duplicate.angle = .pi+0.03
        var adjacent = door; adjacent.id = UUID(); adjacent.center.x += 1.0
        var behind = door; behind.id = UUID(); behind.center.y += 0.5
        room.openings = [door,duplicate,adjacent,behind]
        var document = seed(); document.shell.stories = [.init(index: 0,rooms: [room])]; document.objects = []
        // Round-trip a saved project: reproduces old files rather than only fresh seeds.
        let stored = try JSONDecoder().decode(SceneEditDocument.self,from: JSONEncoder().encode(document))
        let scene = StudioSceneBuilder.scene(stored,story: 0,cutaway: false)
        XCTAssertEqual(scene.rootNode.childNodes.filter { $0.name == "shell:door" }.count,3)
        XCTAssertEqual(stored.shell.allRooms[0].openings.count,4)
        var otherFloor = room; otherFloor.id = UUID(); otherFloor.story = 1; otherFloor.openings = [door]
        document.shell.stories.append(.init(index: 1,rooms: [otherFloor]))
        XCTAssertEqual(StudioSceneBuilder.scene(document,story: nil,cutaway: false).rootNode.childNodes.filter { $0.name == "shell:door" }.count,4)
    }
    @MainActor func testSharedDoorIsRenderedOnceButSeparateDoorsRemain() {
        var a = seed().shell.allRooms[0]; a.transform = .identity
        let door = Opening(id: UUID(),kind: .door,wallID: nil,center: .init(x: 1,y: 1),width: 0.9,height: 2,sillHeight: 0,angle: 0,confidence: .high)
        a.openings = [door]
        var b = a; b.id = UUID()
        var duplicate = door; duplicate.id = UUID(); duplicate.center.y += 0.08; duplicate.angle += .pi
        var separate = door; separate.id = UUID(); separate.center.x += 1.1
        b.openings = [duplicate,separate]
        var document = seed(); document.shell.stories = [.init(index: 0,rooms: [a,b])]; document.objects = []
        let scene = StudioSceneBuilder.scene(document,story: 0,cutaway: false)
        XCTAssertEqual(scene.rootNode.childNodes.filter { $0.name == "shell:door" }.count,2)
        XCTAssertEqual(document.shell.allRooms.flatMap(\.openings).count,3,"Source records must remain intact")
    }
    func testCompoundFloorKeepsConcaveShapeAndCourtyard() {
        var room = seed().shell.allRooms[0]; room.transform = .identity; room.walls = []
        room.floorPolygon = [.init(x: 0,y: 0),.init(x: 3,y: 0),.init(x: 3,y: 1),.init(x: 1,y: 1),.init(x: 1,y: 3),.init(x: 0,y: 3)]
        let path = StudioFloorSlab.outline(rooms: [room])
        XCTAssertTrue(path.contains(CGPoint(x: 0.5,y: 2)))
        XCTAssertFalse(path.contains(CGPoint(x: 2,y: 2)),"Do not fill the concave cutout")
        let regions = [
            [Point2D(x: 0,y: 0),.init(x: 4,y: 0),.init(x: 4,y: 1),.init(x: 0,y: 1)],
            [.init(x: 0,y: 3),.init(x: 4,y: 3),.init(x: 4,y: 4),.init(x: 0,y: 4)],
            [.init(x: 0,y: 1),.init(x: 1,y: 1),.init(x: 1,y: 3),.init(x: 0,y: 3)],
            [.init(x: 3,y: 1),.init(x: 4,y: 1),.init(x: 4,y: 3),.init(x: 3,y: 3)]
        ].map { SceneEditDocument.FloorRegion(roomID: room.id,polygon: $0) }
        let courtyard = StudioFloorSlab.outline(rooms: [room],regions: regions)
        XCTAssertFalse(courtyard.contains(CGPoint(x: 2,y: 2)))
        XCTAssertTrue(courtyard.contains(CGPoint(x: 3.5,y: 2)))
    }
    func testStudioRetainsAllRawFloorRegionsAndRoundTrips() throws {
        let scan = SyntheticRooms.rectangularRoom().scan
        var extra = try XCTUnwrap(scan.floors.first)
        extra.id = UUID(); extra.polygonCorners = [SIMD3(0,0,0),SIMD3(1,0,0),SIMD3(1,0,1),SIMD3(0,0,1)]
        var input = scan; input.surfaces.append(extra)
        let plan = FloorPlanBuilder().build(from: input,name: "Test")
        var document = SceneEditDocument.seed(house: House(room: plan),source: .room,id: plan.id,scans: [input])
        // Synthetic rectangular floors may omit polygon corners; the additional
        // captured polygon must still survive independently of the plan outline.
        XCTAssertFalse(document.floorRegions?.isEmpty ?? true)
        try document.validate()
        let decoded = try JSONDecoder().decode(SceneEditDocument.self,from: JSONEncoder().encode(document))
        XCTAssertEqual(decoded.floorRegions,document.floorRegions)
        document.floorRegions = nil; document.recoverFloorRegions(scans: [input])
        XCTAssertEqual(document.floorRegions,decoded.floorRegions)
    }
    func testSelectionUsesWholeRectangularEnvelope() throws {
        let sofa = SceneEditObject(origin: "test",name: "Sofa",family: .sofa,position: .init(x: 0,y: 0.5,z: 0),size: .init(x: 2,y: 1,z: 2))
        XCTAssertEqual(try XCTUnwrap(StudioPlacement.rayIntersection(sofa,origin: SIMD3(0,0.1,5),direction: SIMD3(0,0,-10))),0.4,accuracy: 0.0001)
        XCTAssertNil(StudioPlacement.rayIntersection(sofa,origin: SIMD3(3,0.5,5),direction: SIMD3(0,0,-10)))
        var rotated = sofa; rotated.yaw = .pi/4
        XCTAssertNotNil(StudioPlacement.rayIntersection(rotated,origin: SIMD3(0,0.5,5),direction: SIMD3(0,0,-10)))
    }
    @MainActor func testDetailedOpeningTemplatesFitOpeningTransformAndPersistDesignChoices() throws {
        let opening = Opening(id: UUID(),kind: .window,wallID: nil,center: .init(x: 2,y: -1),width: 1.2,height: 1.4,sillHeight: 0.9,angle: 0.3,confidence: .high)
        let transform = Transform2D(translation: .init(x: 1,y: 2),rotation: 0.2),position = transform.apply(opening.center)
        for template in SceneEditDocument.WindowTemplate.allCases {
            let root = StudioWindowModel.make(opening,wall: nil,transform: transform,template: template,angle: 35)
            XCTAssertEqual(Double(root.simdPosition.x),position.x,accuracy: 0.0001)
            XCTAssertEqual(Double(root.simdPosition.z),-position.y,accuracy: 0.0001)
            var count = 0,glass = 0
            root.enumerateChildNodes { node,_ in count += 1; if node.name == "glazing" { glass += 1; XCTAssertEqual(node.geometry?.firstMaterial?.writesToDepthBuffer,false) } }
            XCTAssertGreaterThan(glass,0); XCTAssertLessThan(count,50)
        }
        for template in SceneEditDocument.DoorTemplate.allCases {
            var door = opening; door.kind = .door; door.sillHeight = 0
            let root = StudioDoorModel.make(door,wall: nil,transform: transform,template: template,angle: 35)
            var leaves = 0,handles = 0
            root.enumerateChildNodes { node,_ in if node.name == "door-leaf" { leaves += 1 }; if node.name == "door-handle" { handles += 1 } }
            XCTAssertEqual(leaves,template == .double || template == .sliding ? 2 : 1)
            XCTAssertEqual(handles,leaves*2)
            XCTAssertEqual(root.childNodes.filter { $0.name == "door-jamb" }.count,2)
        }
        var document = seed(); let source = document.shell
        document.doorTemplate = .glazed; document.windowTemplate = .casement; document.doorOpeningDegrees = 45; document.windowOpeningDegrees = 30
        try document.validate()
        let decoded = try JSONDecoder().decode(SceneEditDocument.self,from: JSONEncoder().encode(document))
        XCTAssertEqual(decoded.doorTemplate,.glazed); XCTAssertEqual(decoded.windowOpeningDegrees,30)
        XCTAssertEqual(decoded.shell,source)
        document.doorOpeningDegrees = 121; XCTAssertThrowsError(try document.validate())
    }
    @MainActor func testContinuousFloorHasNoInteriorBlockFacesAndOneNode() {
        var a = seed().shell.allRooms[0]; a.transform = .identity; a.walls = []; a.objects = []; a.openings = []
        a.floorPolygon = [.init(x: 0,y: 0),.init(x: 2,y: 0),.init(x: 2,y: 2),.init(x: 0,y: 2)]
        var b = a; b.id = UUID(); b.floorPolygon = a.floorPolygon.map { .init(x: $0.x+2,y: $0.y) }
        let mesh = StudioFloorSlab.mesh(rooms: [a,b])
        let sideAtJoin = mesh.triangles.filter { t in
            let p = [mesh.positions[Int(t.x)],mesh.positions[Int(t.y)],mesh.positions[Int(t.z)]]
            return p.allSatisfy { abs($0.x-2) < 1e-5 } && p.contains { $0.y < -0.001 }
        }
        XCTAssertTrue(sideAtJoin.isEmpty,"Adjacent floor pieces must not have internal vertical block faces")
        var document = seed(); document.shell.stories = [.init(index: 0,rooms: [a,b])]; document.objects = []
        let scene = StudioSceneBuilder.scene(document,story: 0,cutaway: false)
        XCTAssertEqual(scene.rootNode.childNodes.filter { $0.name == "shell:floor" }.count,1)
        XCTAssertEqual(document.shell.allRooms[0].floorPolygon,a.floorPolygon)
    }
    func testContinuousFloorBridgesWallFootprintWithoutChangingRoomArea() {
        var a = seed().shell.allRooms[0]; a.transform = .identity; a.walls = []; a.objects = []; a.openings = []
        a.floorPolygon = [.init(x: 0,y: 0),.init(x: 1,y: 0),.init(x: 1,y: 2),.init(x: 0,y: 2)]
        var b = a; b.id = UUID(); b.floorPolygon = a.floorPolygon.map { .init(x: $0.x+1.2,y: $0.y) }
        a.walls = [.init(id: UUID(),segment: .init(start: .init(x: 1.1,y: 0),end: .init(x: 1.1,y: 2)),height: 2.5,thickness: 0.2,confidence: .high)]
        let mesh = StudioFloorSlab.mesh(rooms: [a,b])
        let topArea = mesh.triangles.reduce(0.0) { sum,t in
            let p = mesh.positions[Int(t.x)],q = mesh.positions[Int(t.y)],r = mesh.positions[Int(t.z)]
            guard abs(p.y) < 1e-6,abs(q.y) < 1e-6,abs(r.y) < 1e-6 else { return sum }
            return sum+Double(simd_length(simd_cross(q-p,r-p)))/2
        }
        XCTAssertEqual(topArea,4.44,accuracy: 0.0001)
        XCTAssertEqual(RoomMeasurements(plan: a).floorArea+RoomMeasurements(plan: b).floorArea,4,accuracy: 0.0001)
    }
    @MainActor func testRotationRingCommitsAngleAndRejectRollsBack() throws {
        let document = seed(),controller = StudioSceneController(),view = SCNView(frame: CGRect(x: 0,y: 0,width: 800,height: 800))
        controller.view = view; let item = try XCTUnwrap(document.objects.first)
        controller.configure(document,story: 0,cutaway: false,selected: item.id,moving: false,reset: 0,rotating: true)
        _ = view.snapshot()
        let radius = Float(max(item.size.x,item.size.z)/2+0.18),center = SIMD3(Float(item.position.x),Float(item.position.y),Float(item.position.z))
        func screen(_ p: SIMD3<Float>) -> CGPoint { let value = view.projectPoint(SCNVector3(p.x,p.y,p.z)); return .init(x: CGFloat(value.x),y: CGFloat(value.y)) }
        var angle: Double?
        controller.onRotate = { _,delta in angle = delta; return false }
        controller.beginDrag(screen(center+SIMD3(radius,0,0)))
        controller.drag(screen(center+SIMD3(radius*cos(.pi/6),0,radius*sin(.pi/6))))
        controller.endDrag()
        XCTAssertEqual(try XCTUnwrap(angle),-Double.pi/6,accuracy: 0.01)
        let node = try XCTUnwrap(view.scene?.rootNode.childNode(withName: "object:"+item.id.uuidString,recursively: false))
        let direction = node.simdOrientation.act(SIMD3<Float>(1,0,0))
        XCTAssertEqual(direction.x,Float(cos(item.yaw)),accuracy: 0.0001)
        XCTAssertEqual(direction.z,Float(-sin(item.yaw)),accuracy: 0.0001)
    }
    func testTechnicalTemplatesPreserveSurveyAndRestoreCapturedColours() throws {
        var document = seed(); document.source = .technical
        document.objects[0].family = .pipe
        let cameraColor = TechnicalPoint3(x: 0.2,y: 0.4,z: 0.6)
        document.objects[0].capturedColor = cameraColor
        let original = document.objects[0]
        for template in SceneEditDocument.TechnicalTemplate.allCases {
            document.applyTechnicalTemplate(template); try document.validate()
            XCTAssertEqual(document.objects[0].position,original.position)
            XCTAssertEqual(document.objects[0].size,original.size)
            XCTAssertEqual(document.objects[0].scanReference,original.scanReference)
            XCTAssertEqual(document.objects[0].capturedColor,cameraColor)
            XCTAssertEqual(document.objects[0].technicalData,original.technicalData)
            let decoded = try JSONDecoder().decode(SceneEditDocument.self,from: JSONEncoder().encode(document))
            XCTAssertEqual(decoded.technicalTemplate,template)
        }
        document.applyTechnicalTemplate(.captured)
        XCTAssertEqual(document.objects[0].color,cameraColor)
        XCTAssertEqual(document.objects[0].colorSource,.cameraSample)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String:Any])
        json.removeValue(forKey: "technicalTemplate")
        XCTAssertNil(try JSONDecoder().decode(SceneEditDocument.self,from: JSONSerialization.data(withJSONObject: json)).technicalTemplate)
    }
    @MainActor func testEquipmentTemplatesStayWithinMeasuredEnvelope() {
        for family in [SceneFurniture.tank,.boiler,.pump,.manifold,.radiator,.electricalPanel,.rectangularDuct,.roundDuct,.pipe] {
            let item = SceneEditObject(origin: "survey",name: family.title,family: family,position: .init(x: 0,y: 1,z: 0),size: .init(x: 0.8,y: 1.6,z: 0.5))
            let model = StudioSceneBuilder.model(item,technical: true,refinedTechnical: true)
            let box = model.boundingBox
            for (low,high,size) in [(Double(box.min.x),Double(box.max.x),item.size.x),(Double(box.min.y),Double(box.max.y),item.size.y),(Double(box.min.z),Double(box.max.z),item.size.z)] {
                XCTAssertGreaterThanOrEqual(low,-size/2-0.0001,family.rawValue)
                XCTAssertLessThanOrEqual(high,size/2+0.0001,family.rawValue)
            }
            XCTAssertLessThanOrEqual(model.childNodes.count,25)
        }
    }
    func testGizmoSnappingDoesNotMoveOtherAxes() {
        let document = seed()
        let item = SceneEditObject(origin: "test",name: "Box",family: .box,position: .init(x: 1.234,y: 1.123,z: 2.357),size: .init(x: 0.5,y: 0.5,z: 0.5))
        let x = StudioPlacement.snapped(item,in: document,axis: .x)
        XCTAssertEqual(x.position.y,item.position.y); XCTAssertEqual(x.position.z,item.position.z)
        let y = StudioPlacement.snapped(item,in: document,axis: .y)
        XCTAssertEqual(y.position.x,item.position.x); XCTAssertEqual(y.position.z,item.position.z)
        XCTAssertEqual(y.position.y,1.1,accuracy: 0.0001)
        let z = StudioPlacement.snapped(item,in: document,axis: .z)
        XCTAssertEqual(z.position.x,item.position.x); XCTAssertEqual(z.position.y,item.position.y)
    }
    @MainActor func testSelectedObjectHasOutlineAndMoveGizmoOnlyInMoveMode() throws {
        let document = seed(),controller = StudioSceneController(),view = SCNView(frame: CGRect(x: 0,y: 0,width: 600,height: 600))
        controller.view = view
        let id = try XCTUnwrap(document.objects.first?.id)
        controller.configure(document,story: 0,cutaway: false,selected: id,moving: false,reset: 0)
        let outline = try XCTUnwrap(view.scene?.rootNode.childNode(withName: "selection-overlay",recursively: false))
        XCTAssertFalse(outline.childNodes.isEmpty)
        let envelope = try XCTUnwrap(outline.childNode(withName: "selection-envelope",recursively: false)?.geometry?.elements.first)
        XCTAssertEqual(envelope.primitiveType,.line)
        XCTAssertEqual(envelope.primitiveCount,12,"Selection must have twelve box edges, without triangle diagonals")
        XCTAssertNil(outline.childNode(withName: "gizmo:x",recursively: true))
        controller.configure(document,story: 0,cutaway: false,selected: id,moving: true,reset: 0)
        for axis in ["x","y","z"] { XCTAssertNotNil(outline.childNode(withName: "gizmo:"+axis,recursively: true)) }
        controller.configure(document,story: 0,cutaway: false,selected: nil,moving: true,reset: 0)
        XCTAssertNil(view.scene?.rootNode.childNode(withName: "selection-overlay",recursively: false))
    }
    @MainActor func testGizmoDragCommitsOneAxisAndRejectedMoveRollsBack() throws {
        let document = seed(),controller = StudioSceneController(),view = SCNView(frame: CGRect(x: 0,y: 0,width: 800,height: 800))
        controller.view = view
        let item = try XCTUnwrap(document.objects.first)
        controller.configure(document,story: 0,cutaway: false,selected: item.id,moving: true,reset: 0)
        let overlay = try XCTUnwrap(view.scene?.rootNode.childNode(withName: "selection-overlay",recursively: false))
        let tip = try XCTUnwrap(overlay.childNodes.first { $0.name == "gizmo:x" && $0.geometry is SCNCone })
        let preview = view.snapshot() // Initialise the offscreen renderer's camera projection before hit-testing.
        #if os(iOS)
        let png = preview.pngData()
        #else
        let png = preview.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png,properties: [:]) }
        #endif
        let previewURL = FileManager.default.temporaryDirectory.appendingPathComponent("dwalk-gizmo-"+UUID().uuidString+".png")
        try XCTUnwrap(png).write(to: previewURL); print("GIZMO_PREVIEW="+previewURL.path)
        let p = view.projectPoint(tip.worldPosition)
        let start = CGPoint(x: CGFloat(p.x),y: CGFloat(p.y))
        var proposed: TechnicalPoint3?
        controller.onMove = { _,position in proposed = position; return false }
        controller.beginDrag(start)
        XCTAssertEqual(controller.movementAxis,.x)
        controller.drag(CGPoint(x: start.x+40,y: start.y))
        controller.endDrag()
        let changed = try XCTUnwrap(proposed)
        XCTAssertNotEqual(changed.x,item.position.x)
        XCTAssertEqual(changed.y,item.position.y,accuracy: 0.0001)
        XCTAssertEqual(changed.z,item.position.z,accuracy: 0.0001)
        let node = try XCTUnwrap(view.scene?.rootNode.childNode(withName: "object:"+item.id.uuidString,recursively: false))
        XCTAssertEqual(Double(node.simdPosition.x),item.position.x,accuracy: 0.0001)
    }
    private func seed() -> SceneEditDocument {
        var house = HouseBuilder().build(from: SyntheticRooms.twoRoomApartment(),name: "Studio test")
        let object = PlacedObject(id: UUID(),category: "sofa",center: .init(x: 1,y: -1),size: .init(width: 2,depth: 0.9),height: 0.85,angle: 0.3,confidence: .high)
        house.stories[0].rooms[0].objects = [object]
        return .seed(house: house,source: .house,id: house.id)
    }
    func testEngineeringLookupTracksDecodeAndInPlaceEdits() throws {
        let id = UUID()
        var record = StudioEngineering.Record(id: id); record.note = "Initial"
        var data = try JSONDecoder().decode(StudioEngineering.self,from: JSONEncoder().encode(StudioEngineering(records: [record])))
        XCTAssertEqual(data.record(id).note,"Initial")
        data.records[0].note = "Updated"
        XCTAssertEqual(data.record(id).note,"Updated")
        data.records.removeAll()
        XCTAssertEqual(data.record(id).note,"")
    }
    @MainActor func testAddingFromReferenceViewSwitchesToProposedAtomically() throws {
        var document = seed(),data = StudioEngineering(); data.view = .existing; document.engineering = data
        let session = SceneEditSession(document)
        let item = SceneEditObject(origin: "Test design",name: "Chair",family: .chair,position: .init(x: 20,y: 0.425,z: 20),size: SceneFurniture.chair.defaultSize)
        try session.addDesignObject(item,allowOverlap: true)
        XCTAssertEqual(session.document.engineering?.view,.proposed)
        XCTAssertTrue(session.document.presentationObjects.contains { $0.id == item.id })
        session.undo(); XCTAssertEqual(session.document,document)
    }
    func testEngineeringSearchRetainsSelectionOutsideResultLimit() {
        let document = seed(),selected = document.objects[0].id
        let results = document.engineeringSearch("",selection: selected,limit: 1)
        XCTAssertTrue(results.contains { $0.id == selected })
        XCTAssertLessThanOrEqual(results.count,2)
    }
    @MainActor func testEngineeringNotesDoNotRecreateTheStudioScene() {
        let document = seed(),controller = StudioSceneController(),view = SCNView()
        controller.view = view
        controller.configure(document,story: 0,cutaway: false,selected: nil,moving: false,reset: 0)
        let first = view.scene
        var edited = document,data = StudioEngineering()
        var record = StudioEngineering.Record(id: edited.objects[0].id); record.note = "Inspect radiator connection"
        data.set(record); edited.engineering = data
        controller.configure(edited,story: 0,cutaway: false,selected: nil,moving: false,reset: 0)
        XCTAssertTrue(view.scene === first,"Metadata edits must not regenerate geometry or lighting")
        controller.configure(edited,story: 0,cutaway: false,selected: edited.objects[0].id,moving: false,reset: 0,showDimensions: true)
        XCTAssertFalse(view.scene === first)
        XCTAssertNotNil(view.scene?.rootNode.childNode(withName: "dimensions",recursively: false))
    }
    func testSmartBauStyleWallProfileKeepsDoorHoleAndSharesCornerMiter() {
        let a = Wall(id: UUID(),segment: .init(start: .zero,end: .init(x: 3,y: 0)),height: 2.5,thickness: 0.1,confidence: .high)
        let b = Wall(id: UUID(),segment: .init(start: .zero,end: .init(x: 0,y: 2)),height: 2.5,thickness: 0.1,confidence: .high)
        var room = seed().shell.allRooms[0]; room.transform = .identity; room.walls = [a,b]
        room.openings = [.init(id: UUID(),kind: .door,wallID: a.id,center: .init(x: 1.5,y: 0),width: 0.9,height: 2,sillHeight: 0,angle: 0,confidence: .high)]
        let ma = StudioWallProfile.mesh(a,room: room,visible: [a.id,b.id]),mb = StudioWallProfile.mesh(b,room: room,visible: [a.id,b.id])
        for mesh in [ma,mb] {
            XCTAssertTrue(mesh.positions.contains { abs($0.x+0.05) < 1e-5 && abs($0.z-0.05) < 1e-5 })
        }
        XCTAssertFalse(ma.triangles.contains { triangle in
            let p = (ma.positions[Int(triangle.x)]+ma.positions[Int(triangle.y)]+ma.positions[Int(triangle.z)])/3
            return p.x > 1.051 && p.x < 1.949 && p.y > 0.001 && p.y < 1.999
        },"Door opening must not acquire solid geometry")
    }
    func testFloorCoverageRemovesCoplanarRoomOverlap() {
        var a = seed().shell.allRooms[0]; a.transform = .identity; a.walls = []; a.openings = []; a.objects = []
        a.floorPolygon = [.init(x: 0,y: 0),.init(x: 2,y: 0),.init(x: 2,y: 2),.init(x: 0,y: 2)]
        var b = a; b.id = UUID(); b.floorPolygon = b.floorPolygon.map { $0+Point2D(x: 1,y: 0) }
        var coverage = StudioFloorCoverage()
        func topArea(_ mesh: TriangleMesh) -> Float {
            mesh.triangles.reduce(0) { area,t in
                let a = mesh.positions[Int(t.x)],b = mesh.positions[Int(t.y)],c = mesh.positions[Int(t.z)]
                return mesh.normals[Int(t.x)].y > 0.9 ? area+simd_length(simd_cross(b-a,c-a))/2 : area
            }
        }
        XCTAssertEqual(topArea(coverage.mesh(a))+topArea(coverage.mesh(b)),6,accuracy: 0.0001)
        var dedup = StudioSurfaceDeduplicator(),mesh = TriangleMesh()
        mesh.addTriangle(.zero,.init(1,0,0),.init(0,0,1))
        XCTAssertEqual(dedup.clean(mesh).triangles.count,1)
        XCTAssertTrue(dedup.clean(mesh).isEmpty)
    }
    @MainActor func testWindowFramesAndDimensionsUseNativeGeometry() {
        let document = seed(),opening = Opening(id: UUID(),kind: .window,wallID: nil,center: .zero,width: 1.2,height: 1.4,sillHeight: 0.9,angle: 0,confidence: .high)
        let window = StudioWindowModel.make(opening,wall: nil,transform: .identity)
        XCTAssertEqual(window.childNodes.filter { $0.name?.hasPrefix("frame:") == true }.count,4)
        let glass = window.childNode(withName: "glazing",recursively: true)?.geometry?.firstMaterial
        XCTAssertEqual(glass?.writesToDepthBuffer,false)
        let scene = StudioSceneBuilder.scene(document,story: 0,cutaway: false,showDimensions: true,dimensionSelection: document.objects[0].id)
        let dimensions = scene.rootNode.childNode(withName: "dimensions",recursively: false)
        var labels = 0; dimensions?.enumerateChildNodes { node,_ in if node.name == "dimension-label" { labels += 1 } }
        XCTAssertGreaterThanOrEqual(labels,4)
        XCTAssertNil(document.floorFinish,"Presentation defaults must not modify the source project")
    }
    func testReferencedThicknessOverridesPreserveOriginalShellAndPersist() throws {
        var document = seed()
        let room = try XCTUnwrap(document.shell.allRooms.first),wall = try XCTUnwrap(room.walls.first)
        var data = StudioEngineering()
        var wallRecord = StudioEngineering.Record(id: wall.id)
        wallRecord.thicknessOverride = 0.24; wallRecord.thicknessReference = "Measured opening reveal"
        var floorRecord = StudioEngineering.Record(id: room.id)
        floorRecord.thicknessOverride = 0.22; floorRecord.thicknessReference = "Structural drawing A-01"
        data.set(wallRecord); data.set(floorRecord); document.engineering = data
        try document.validate()
        let decoded = try JSONDecoder().decode(SceneEditDocument.self,from: JSONEncoder().encode(document))
        XCTAssertEqual(decoded.architecturalShell.allRooms[0].walls[0].thickness,0.24)
        XCTAssertEqual(decoded.plan.allRooms[0].displayFloorSlabThickness,0.22)
        XCTAssertEqual(decoded.shell.allRooms[0].walls[0].thickness,wall.thickness)
        XCTAssertNil(decoded.shell.allRooms[0].floorSlabThickness)
        XCTAssertTrue(String(decoding: decoded.engineeringCSV(),as: UTF8.self).contains("Measured opening reveal"))
        wallRecord.thicknessReference = ""; data.set(wallRecord); document.engineering = data
        XCTAssertThrowsError(try document.validate())
        wallRecord.thicknessReference = "Survey"; wallRecord.thicknessOverride = -.infinity
        data.set(wallRecord); document.engineering = data
        XCTAssertThrowsError(try document.validate())
    }
    func testEngineeringLegacyProjectAndValidation() throws {
        let document = seed()
        let legacy = try JSONDecoder().decode(SceneEditDocument.self,from: JSONEncoder().encode(document))
        XCTAssertNil(legacy.engineering)
        var edited = document
        var data = StudioEngineering()
        data.set(.init(id: UUID()))
        edited.engineering = data
        XCTAssertThrowsError(try edited.validate())
        let id = document.objects[0].id
        var record = StudioEngineering.Record(id: id)
        record.verification = .init(dimensions: document.objects[0].size,reference: "",date: Date())
        data.records = [record]; edited.engineering = data
        XCTAssertThrowsError(try edited.validate())
    }
    @MainActor func testRenovationPhasesFilterSceneAndPlanWithoutChangingEvidence() throws {
        var document = seed()
        let original = document.shell
        let wall = try XCTUnwrap(document.shell.allRooms.first?.walls.first)
        let object = document.objects[0]
        var data = StudioEngineering()
        var wallRecord = StudioEngineering.Record(id: wall.id); wallRecord.phase = .remove
        var objectRecord = StudioEngineering.Record(id: object.id); objectRecord.phase = .new
        data.set(wallRecord); data.set(objectRecord); data.view = .proposed; document.engineering = data
        try document.validate()
        XCTAssertFalse(document.plan.allRooms.flatMap(\.walls).contains { $0.id == wall.id })
        XCTAssertEqual(document.presentationObjects.count,1)
        data.view = .existing; document.engineering = data
        XCTAssertTrue(document.plan.allRooms.flatMap(\.walls).contains { $0.id == wall.id })
        XCTAssertTrue(document.presentationObjects.isEmpty)
        data.view = .demolition; document.engineering = data
        XCTAssertEqual(document.plan.allRooms.flatMap(\.walls).map(\.id),[wall.id])
        XCTAssertEqual(document.shell,original)
        let scene = StudioSceneBuilder.scene(document,story: nil,cutaway: false,decorated: false)
        XCTAssertFalse(scene.rootNode.childNodes.contains { $0.name == "object:"+object.id.uuidString })
    }
    @MainActor func testVerificationBecomesStaleAfterDimensionEditAndUndoRestoresIt() throws {
        var document = seed()
        let element = try XCTUnwrap(document.engineeringElements.first { $0.id == document.objects[0].id })
        var record = StudioEngineering.Record(id: element.id)
        record.verification = .init(dimensions: element.dimensions,reference: "Laser survey · AB",date: Date())
        var data = StudioEngineering(); data.set(record); document.engineering = data
        let session = SceneEditSession(document)
        XCTAssertEqual(document.measurementStatus(element),"User verified")
        var object = document.objects[0]; object.size.x += 0.2; try session.update(object)
        let updated = try XCTUnwrap(session.document.engineeringElements.first { $0.id == object.id })
        XCTAssertEqual(session.document.measurementStatus(updated),"Changed · recheck required")
        session.undo()
        XCTAssertEqual(session.document.measurementStatus(element),"User verified")
        try session.change { $0.objects.removeAll() }
        XCTAssertTrue(session.document.engineering?.records.isEmpty == true)
        session.undo()
        XCTAssertEqual(session.document.engineering?.records.first?.verification?.reference,"Laser survey · AB")
    }
    func testEngineeringCSVQuotesAndNeutralisesSpreadsheetFormulas() throws {
        var document = seed(); document.objects[0].name = "=SUM(1,2)"
        var record = StudioEngineering.Record(id: document.objects[0].id)
        record.issue = "Check \"valve\"\naccess"; record.assignee = "@engineer"
        var data = StudioEngineering(); data.set(record); document.engineering = data
        let csv = String(decoding: document.engineeringCSV(),as: UTF8.self)
        XCTAssertTrue(csv.contains("'@engineer"))
        XCTAssertTrue(csv.contains("'=SUM(1,2)"))
        XCTAssertTrue(csv.contains("Check \"\"valve\"\"\naccess"))
        XCTAssertTrue(csv.contains("Unverified"))
    }
    func testExistingViewUsesReferenceEnvelopeAndFamily() {
        var document = seed(); var data = StudioEngineering(); data.view = .existing
        document.engineering = data
        let original = document.objects[0]
        document.objects[0].replaceFamily(.bed)
        XCTAssertEqual(document.presentationObjects[0].family,original.family)
        XCTAssertEqual(document.presentationObjects[0].size,original.size)
        XCTAssertEqual(document.objects[0].family,.bed)
    }
    func testSeedUsesScanObjectsButKeepsShellAndIdentifiersSeparate() throws {
        let document = seed(); try document.validate()
        XCTAssertEqual(document.objects.count,1)
        XCTAssertEqual(document.objects[0].family,.sofa)
        XCTAssertNotEqual(document.objects[0].id,document.objects[0].sourceID)
        XCTAssertTrue(document.shell.allRooms.allSatisfy { $0.objects.isEmpty })
        XCTAssertEqual(document.objects[0].size.x,2)
    }
    @MainActor func testUndoRedoAndAppearancePreserveMeasurementsAndSource() throws {
        let document = seed(),session = SceneEditSession(seed())
        let source = session.document
        var object = try XCTUnwrap(session.selected ?? session.document.objects.first)
        object.position.x += 1; try session.update(object)
        XCTAssertTrue(session.dirty)
        session.undo(); XCTAssertEqual(session.document,source)
        session.redo(); XCTAssertEqual(session.document.objects[0].position.x,object.position.x)
        try session.change { $0.apply(.pastel); $0.lighting = .night; $0.season = .winter }
        XCTAssertEqual(session.document.shell,source.shell)
        XCTAssertEqual(session.document.objects[0].size,source.objects[0].size)
        XCTAssertEqual(session.document.sourceID,source.sourceID)
        session.markSaved(); XCTAssertFalse(session.dirty)
        XCTAssertEqual(document.objects[0].position.x,1)
    }
    func testInvalidProjectValuesAreRejected() throws {
        var document = seed(); document.objects[0].size.x = -.infinity
        XCTAssertThrowsError(try document.validate())
        document = seed(); document.objects[0].axis = .init(x: 2,y: 0,z: 0)
        XCTAssertThrowsError(try document.validate())
        document = seed(); document.objects[0].story = 999
        XCTAssertThrowsError(try document.validate())
        document = seed(); document.objects.append(document.objects[0])
        XCTAssertThrowsError(try document.validate())
    }
    func testIndependentSaveDoesNotChangeHousePackageAndRoundTrips() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let package = HousePackage.assemble(structure: SyntheticRooms.twoRoomApartment(),name: "Original",capturedStructureData: nil,usdzData: Data("original-usdz".utf8))
        let original = root.appendingPathComponent("original.housescan")
        try package.write(to: original)
        let beforeHouse = try Data(contentsOf: original.appendingPathComponent("house.json"))
        let beforeModel = try Data(contentsOf: original.appendingPathComponent("house.usdz"))
        let document = SceneEditDocument.seed(house: package.house,source: .house,id: package.house.id)
        let url = SceneEditStore.url(root: root,source: document.source,id: document.sourceID)
        try SceneEditStore.write(document,to: url)
        XCTAssertEqual(try SceneEditStore.read(url,source: document.source,id: document.sourceID),document)
        XCTAssertThrowsError(try SceneEditStore.read(url,source: .technical,id: document.sourceID))
        XCTAssertEqual(try Data(contentsOf: original.appendingPathComponent("house.json")),beforeHouse)
        XCTAssertEqual(try Data(contentsOf: original.appendingPathComponent("house.usdz")),beforeModel)
    }
    @MainActor func testEveryNativeModelBuildsWithBoundedComplexity() throws {
        for family in SceneFurniture.allCases {
            let size = family.defaultSize
            let item = SceneEditObject(origin: "test",name: family.title,family: family,position: .init(x: 0,y: size.y/2,z: 0),size: size)
            try item.validate()
            let node = StudioSceneBuilder.model(item)
            XCTAssertTrue(node.name?.contains(item.id.uuidString) == true)
            XCTAssertLessThan(node.childNodes.count,40)
            XCTAssertFalse(node.childNodes.isEmpty)
            XCTAssertTrue(node.childNodes.allSatisfy { $0.geometry?.firstMaterial?.lightingModel == .physicallyBased })
        }
    }
    @MainActor func testEditedExportsContainModelsAnd2DOutputs() throws {
        let document = seed()
        let project = try StudioExporter.data(document,format: .project)
        XCTAssertEqual(try JSONDecoder().decode(SceneEditDocument.self,from: project),document)
        for format in [StudioExporter.Format.pdf,.svg,.dxf] {
            let data = try StudioExporter.data(document,format: format)
            XCTAssertGreaterThan(data.count,100)
            if format == .svg { XCTAssertTrue(String(decoding: data,as: UTF8.self).contains("<svg")) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let usdz = try StudioExporter.data(document,format: .usdz)
        XCTAssertEqual(Array(usdz.prefix(2)),[0x50,0x4b])
        let url = root.appendingPathComponent("edited.usdz"); try usdz.write(to: url)
        XCTAssertGreaterThan(MDLAsset(url: url).count,0)
        let obj = try StudioExporter.data(document,format: .obj)
        XCTAssertEqual(Array(obj.prefix(2)),[0x50,0x4b])
    }
    func testTechnicalStudioDoesNotPromoteUnreviewedDetections() throws {
        let room = TechnicalRoom.capturedShell(id: UUID(),notes: "")
        var package = TechnicalRoomPackage(manifest: .init(id: room.id,name: "Technik"),document: .init(room: room),alignment: .init(),journal: .init(),worldMapData: nil,thumbnailPNG: nil)
        let suggestion = TechnicalMEPSuggestion(kind: .pipe,start: .init(x: 0,y: 0,z: 0),end: .init(x: 0,y: 1,z: 0),width: 0.1,height: 0.1,crossAxis: .init(x: 1,y: 0,z: 0),method: "test",supportCount: 30,residualMetres: 0.005)
        package.recognition.suggestions = [suggestion]
        XCTAssertTrue(try SceneEditDocument.technical(package).objects.isEmpty)
        package.recognition.suggestions[0].status = .accepted
        let document = try SceneEditDocument.technical(package)
        XCTAssertEqual(document.objects.count,1)
        XCTAssertEqual(document.objects[0].family,.pipe)
        XCTAssertEqual(document.objects[0].sourceID,suggestion.id)
        XCTAssertEqual(package.recognition.suggestions[0].start,suggestion.start)
    }
    func testTechnicalStudioGeneratesModularLayoutAndWallsWhenEmpty() throws {
        let room = TechnicalRoom.capturedShell(id: UUID(),notes: "")
        let package = TechnicalRoomPackage(manifest: .init(id: room.id,name: "Technik"),document: .init(room: room),alignment: .init(),journal: .init(),worldMapData: nil,thumbnailPNG: nil)
        let document = try SceneEditDocument.technical(package)
        XCTAssertFalse(document.objects.isEmpty, "Fresh survey should auto-generate modular equipment layout")
        XCTAssertEqual(document.shell.allRooms.first?.walls.count, 4, "Studio technical room should have 4 enclosing boundary walls")
        XCTAssertGreaterThan(document.shell.allRooms.first?.ceilingHeight.upperBound ?? 0, 0, "Ceiling height must be positive")
        let families = Set(document.objects.map(\.family))
        XCTAssertTrue(families.contains(.boiler))
        XCTAssertTrue(families.contains(.tank))
        XCTAssertTrue(families.contains(.pump))
        XCTAssertTrue(families.contains(.manifold))
        XCTAssertTrue(families.contains(.electricalPanel))
        XCTAssertTrue(families.contains(.pipe))
        try document.validate()
    }
    @MainActor func testSmartFurnitureAdaptsAndRetainsScanReference() throws {
        let document = seed()
        let original = try XCTUnwrap(document.objects.first)
        XCTAssertEqual(original.scanReference?.size,original.size)
        let small = StudioSceneBuilder.model(original)
        var wide = original; wide.size.x = 3.5
        let large = StudioSceneBuilder.model(wide)
        XCTAssertGreaterThan(large.childNodes.count,small.childNodes.count,"Wider sofa adds cushions")
        XCTAssertEqual(wide.scanReference?.size.x,original.size.x)
        wide.replaceFamily(.bed)
        XCTAssertEqual(wide.size,SceneFurniture.bed.defaultSize,"Replacement uses the new model defaults")
        XCTAssertEqual(wide.scanReference?.size,original.size)
    }
    func testBedToSofaResetsDimensionsAndKeepsOriginalScanReference() {
        var item = seed().objects[0]
        let reference = item.scanReference
        item.replaceFamily(.bed)
        XCTAssertEqual(item.name,"Bed")
        XCTAssertEqual(item.size.z,2)
        item.replaceFamily(.sofa)
        XCTAssertEqual(item.name,"Sofa")
        XCTAssertEqual(item.size,SceneFurniture.sofa.defaultSize)
        XCTAssertEqual(item.position.y,item.size.y/2,accuracy: 0.0001)
        XCTAssertEqual(item.scanReference,reference)
    }
    func testTechnicalReclassificationPreservesRouteMeasurements() {
        var item = SceneEditObject(origin: "Survey",name: "Pipe",family: .pipe,position: .init(x: 1,y: 2,z: 3),size: .init(x: 0.12,y: 2.4,z: 0.12),axis: .init(x: 1,y: 0,z: 0))
        let original = item
        item.replaceFamily(.roundDuct,preserveMeasurements: true)
        XCTAssertEqual(item.size,original.size)
        XCTAssertEqual(item.position,original.position)
        XCTAssertEqual(item.axis,original.axis)
    }
    func testPortraitCameraFramesWholeRoomRatherThanClippingSideWalls() {
        let portrait = StudioCameraFraming.distance(width: 8,height: 2.8,depth: 5,aspect: 393.0/852)
        let landscape = StudioCameraFraming.distance(width: 8,height: 2.8,depth: 5,aspect: 852.0/393)
        XCTAssertGreaterThan(portrait,landscape)
        let radius = sqrt(8*8+2.8*2.8+5*5)/2
        let projectedHalfAngle = asin(radius/portrait)
        XCTAssertLessThan(projectedHalfAngle,atan(tan(21 * .pi/180)*393/852))
    }
    @MainActor func testReturningFrom2DReattachesSceneToNewViewport() {
        let document = seed(),controller = StudioSceneController()
        let first = SCNView(frame: CGRect(x: 0,y: 0,width: 393,height: 852))
        controller.view = first; controller.configure(document,story: 0,cutaway: false,selected: nil,moving: false,reset: 0)
        XCTAssertNotNil(first.scene)
        let replacement = SCNView(frame: CGRect(x: 0,y: 0,width: 393,height: 852))
        controller.view = replacement; controller.configure(document,story: 0,cutaway: false,selected: nil,moving: false,reset: 0)
        XCTAssertNotNil(replacement.scene)
        XCTAssertTrue(replacement.scene?.rootNode.childNodes.contains { $0.name?.hasPrefix("object:") == true } == true)
    }
    @MainActor func testFullWallViewIncludesEveryScannedWallWithoutChangingShell() {
        let document = seed(),original = document.shell
        let full = StudioSceneBuilder.scene(document,story: document.shell.stories[0].index,cutaway: false)
        let expected = document.shell.stories[0].rooms.reduce(0) { $0+$1.walls.filter { $0.length > 0 }.count }
        XCTAssertEqual(full.rootNode.childNodes.filter { $0.name == "shell:wall" }.count,expected)
        XCTAssertEqual(document.shell,original)
    }
    func testHorizontalPipeHasFullLengthInEditedPlan() {
        let item = SceneEditObject(origin: "test",name: "Pipe",family: .pipe,position: .init(x: 0,y: 1,z: 0),size: .init(x: 0.1,y: 2,z: 0.1),axis: .init(x: 1,y: 0,z: 0))
        XCTAssertEqual(item.planObject.size.width,2,accuracy: 0.0001)
        XCTAssertEqual(item.planObject.size.depth,0.1,accuracy: 0.0001)
    }
    func testOverlapChecksAllowTouchingAndSnapToGrid() throws {
        var document = seed(); document.objects = []
        let item = SceneEditObject(origin: "test",name: "Box",family: .box,position: .init(x: 1,y: 0.5,z: 1),size: .init(x: 1,y: 1,z: 1))
        var other = item; other.id = UUID(); other.position.x = 1.5
        XCTAssertTrue(StudioPlacement.intersects(item,other))
        other.position.x = 2
        XCTAssertFalse(StudioPlacement.intersects(item,other),"Touching faces are permitted")
        other.position.x = 1.7; other.yaw = .pi/4
        XCTAssertTrue(StudioPlacement.intersects(item,other))
        document.objects = [item]
        XCTAssertThrowsError(try StudioPlacement.check(other,in: document))
        var point = item; point.position = .init(x: 1.123,y: 0.5,z: 1.123)
        let snapped = StudioPlacement.snapped(point,in: document)
        XCTAssertEqual(snapped.position.x,1.1,accuracy: 0.0001)
        XCTAssertEqual(snapped.size,item.size)
    }
    @MainActor func testTechnicalModelsKeepSharpMeasuredEnvelopeAndDuctRoll() throws {
        let item = SceneEditObject(origin: "test",name: "Duct",family: .rectangularDuct,position: .init(x: 0,y: 1,z: 0),size: .init(x: 0.4,y: 2,z: 0.2),axis: .init(x: 1,y: 0,z: 0),crossAxis: .init(x: 0,y: 0,z: 1))
        try item.validate()
        let node = StudioSceneBuilder.model(item,technical: true)
        let box = try XCTUnwrap(node.childNodes.first?.geometry as? SCNBox)
        XCTAssertEqual(box.width,0.4,accuracy: 1e-8)
        XCTAssertEqual(box.height,2,accuracy: 1e-8)
        XCTAssertEqual(box.length,0.2,accuracy: 1e-8)
        XCTAssertEqual(box.chamferRadius,0)
        let right = node.simdOrientation.act(SIMD3<Float>(1,0,0))
        XCTAssertEqual(right.z,1,accuracy: 0.0001)
    }
    func testEquipmentCapacityRequiresReferenceAndSurvivesProjectRoundTrip() throws {
        var data = StudioEquipmentData()
        data.outputKW = 12
        XCTAssertThrowsError(try data.validate())
        data.reference = "Nameplate photo / manufacturer model"
        try data.validate()
        var document = seed(); document.objects[0].technicalData = data
        try document.validate()
        let reopened = try JSONDecoder().decode(SceneEditDocument.self,from: JSONEncoder().encode(document))
        XCTAssertEqual(reopened.objects[0].technicalData?.outputKW,12)
        data.ratedPressureBar = .nan
        XCTAssertThrowsError(try data.validate())
    }
    @MainActor func testImageExportAndCreateReviewFixture() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dwalk-studio-review-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        var structure = SyntheticRooms.twoRoomApartment()
        let roomBounds = HouseBuilder().build(from: structure,name: "Fixture").allRooms[0].bounds
        structure.rooms[0].objects = [.init(category: "sofa",dimensions: SIMD3(2,0.85,0.9),transform: .roomPlacement(x: Float(roomBounds.center.x),y: 0.425,z: Float(-roomBounds.center.y)))]
        let package = HousePackage.assemble(structure: structure,name: "Studio review fixture",capturedStructureData: nil,usdzData: nil)
        let url = root.appendingPathComponent("Studio review.housescan")
        try package.write(to: url)
        let document = SceneEditDocument.seed(house: package.house,source: .house,id: package.house.id)
        let view = SCNView(frame: CGRect(x: 0,y: 0,width: 800,height: 600)),controller = StudioSceneController()
        controller.view = view
        controller.configure(document,story: 0,cutaway: true,selected: nil,moving: false,reset: 0)
        let png = try controller.png()
        XCTAssertEqual(Array(png.prefix(4)),[0x89,0x50,0x4e,0x47])
        let preview = root.appendingPathComponent("Studio-preview.png")
        try png.write(to: preview)
        print("STUDIO_REVIEW_PACKAGE="+url.path)
        print("STUDIO_REVIEW_IMAGE="+preview.path)
    }
    func testWallJoinFillsSharedCornerButDoesNotBridgeDoorwayOrRealGap() {
        let a = Wall(id: UUID(),segment: .init(start: .init(x: -2,y: 0),end: .zero),height: 2.5,thickness: 0.1,confidence: .high)
        var b = Wall(id: UUID(),segment: .init(start: .zero,end: .init(x: 0,y: 2)),height: 2.5,thickness: 0.1,confidence: .high)
        var room = FloorPlan(id: UUID(),name: "Corner",label: .unidentified,story: 0,transform: .identity,walls: [a,b],openings: [],objects: [],floorPolygon: [],ceilingHeight: 2.5...2.5)
        XCTAssertFalse(StudioWallJoins.mesh(room: room,visible: [a.id,b.id]).isEmpty)
        XCTAssertTrue(StudioWallJoins.mesh(room: room,visible: [a.id]).isEmpty)
        b.segment.start = .init(x: 0,y: 0.2); room.walls = [a,b]
        XCTAssertTrue(StudioWallJoins.mesh(room: room,visible: [a.id,b.id]).isEmpty)
        b.segment.start = .zero; room.walls = [a,b]
        room.openings = [.init(id: UUID(),kind: .door,wallID: b.id,center: .init(x: 0,y: 0.25),width: 0.5,height: 2,sillHeight: 0,angle: .pi/2,confidence: .high)]
        XCTAssertTrue(StudioWallJoins.mesh(room: room,visible: [a.id,b.id]).isEmpty)
    }
    #if os(iOS)
    @MainActor func testCompactARControlsFitWithAccessibleText() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for size in [DynamicTypeSize.large,.accessibility3] {
            let state = ViewerState(); state.mode = .ar
            let controls = ViewerControls(state: state,usdzURL: URL(fileURLWithPath: "/tmp/layout-preview.usdz")).tint(.blue).environment(\.dynamicTypeSize,size).environment(\.locale,Locale(identifier: "en"))
            let hosting = UIHostingController(rootView: controls)
            let fitting = hosting.sizeThatFits(in: CGSize(width: 320,height: 1000))
            XCTAssertLessThanOrEqual(fitting.width,320)
            XCTAssertLessThan(fitting.height,320,"AR controls must leave room for the camera on a compact phone")
            let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0,y: 0,width: 320,height: 600)
            window.rootViewController = hosting; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200)); hosting.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: hosting.view.bounds).image { _ in hosting.view.drawHierarchy(in: hosting.view.bounds,afterScreenUpdates: true) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("dwalk-ar-controls-\(size)-\(UUID()).png")
            try XCTUnwrap(image.pngData()).write(to: url); print("AR_CONTROLS_LAYOUT="+url.path)
            window.isHidden = true; window.rootViewController = nil
        }
    }
    @MainActor func testRootProvidesFiveNativeNavigationTabs() async throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "RoomScannerStorageRoot")
        let location = StorageLocation.temporary()
        defaults.set(location.documentsURL.path,forKey: "RoomScannerStorageRoot")
        defer {
            if let previous { defaults.set(previous,forKey: "RoomScannerStorageRoot") }
            else { defaults.removeObject(forKey: "RoomScannerStorageRoot") }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0,y: 0,width: 393,height: 852)
        let hosting = UIHostingController(rootView: RootView().environment(\.locale,Locale(identifier: "en")))
        window.rootViewController = hosting; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(350))
        hosting.view.layoutIfNeeded()
        func tabControllers(_ controller: UIViewController) -> [UITabBarController] {
            (controller as? UITabBarController).map { [$0] } ?? controller.children.flatMap(tabControllers)
        }
        let tabs = try XCTUnwrap(tabControllers(hosting).first)
        XCTAssertEqual(tabs.tabBar.items?.compactMap(\.title),["House","Technik","Capture","Studio","Profile"])
        let image = UIGraphicsImageRenderer(bounds: hosting.view.bounds).image { _ in hosting.view.drawHierarchy(in: hosting.view.bounds,afterScreenUpdates: true) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dwalk-five-tabs-"+UUID().uuidString+".png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("FIVE_TAB_LAYOUT="+url.path)
    }
    @MainActor func testPhoneStudioKeepsCanvasFullHeightWithInspectorClosed() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for size in [DynamicTypeSize.large,.accessibility3] {
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0,y: 0,width: 393,height: 852)
        let location = StorageLocation.temporary()
        let hosting = UIHostingController(rootView: NavigationStack {
            StudioEditorView(document: seed(),storageURL: location.documentsURL.appendingPathComponent("design.json")).environment(\.dynamicTypeSize,size)
        })
        window.rootViewController = hosting; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(300))
        hosting.view.layoutIfNeeded()
        func sceneViews(_ view: UIView) -> [SCNView] { (view as? SCNView).map { [$0] } ?? view.subviews.flatMap(sceneViews) }
        let canvas = try XCTUnwrap(sceneViews(hosting.view).first)
        XCTAssertGreaterThan(canvas.bounds.height,650,"Floating controls must not shrink the canvas into a short panel")
        let image = UIGraphicsImageRenderer(bounds: hosting.view.bounds).image { _ in hosting.view.drawHierarchy(in: hosting.view.bounds,afterScreenUpdates: true) }
        let png = try XCTUnwrap(image.pngData())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dwalk-fullscreen-studio-\(size)-"+UUID().uuidString+".png")
        try png.write(to: url); print("STUDIO_PHONE_LAYOUT="+url.path)
        }
    }
    @MainActor func testLandscapeStudioKeepsCanvasBehindFloatingControls() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0,y: 0,width: 852,height: 393)
        let hosting = UIHostingController(rootView: NavigationStack {
            StudioEditorView(document: seed(),storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("landscape-design.json"))
        })
        window.rootViewController = hosting; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(300)); hosting.view.layoutIfNeeded()
        func canvases(_ view: UIView) -> [SCNView] { (view as? SCNView).map { [$0] } ?? view.subviews.flatMap(canvases) }
        let canvas = try XCTUnwrap(canvases(hosting.view).first)
        XCTAssertGreaterThan(canvas.bounds.width,750)
        XCTAssertGreaterThan(canvas.bounds.height,300)
        let image = UIGraphicsImageRenderer(bounds: hosting.view.bounds).image { _ in hosting.view.drawHierarchy(in: hosting.view.bounds,afterScreenUpdates: true) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dwalk-landscape-studio-"+UUID().uuidString+".png")
        try XCTUnwrap(image.pngData()).write(to: url); print("STUDIO_LANDSCAPE_LAYOUT="+url.path)
    }
    #endif
}

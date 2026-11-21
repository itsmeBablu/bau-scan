import XCTest
import SceneKit
import ModelIO
@testable import RoomScanner

final class SceneStudioTests: XCTestCase {
    private func seed() -> SceneEditDocument {
        var house = HouseBuilder().build(from: SyntheticRooms.twoRoomApartment(),name: "Studio test")
        let object = PlacedObject(id: UUID(),category: "sofa",center: .init(x: 1,y: -1),size: .init(width: 2,depth: 0.9),height: 0.85,angle: 0.3,confidence: .high)
        house.stories[0].rooms[0].objects = [object]
        return .seed(house: house,source: .house,id: house.id)
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
    @MainActor func testSmartFurnitureAdaptsAndRetainsScanReference() throws {
        let document = seed()
        let original = try XCTUnwrap(document.objects.first)
        XCTAssertEqual(original.scanReference?.size,original.size)
        let small = StudioSceneBuilder.model(original)
        var wide = original; wide.size.x = 3.5
        let large = StudioSceneBuilder.model(wide)
        XCTAssertGreaterThan(large.childNodes.count,small.childNodes.count,"Wider sofa adds cushions")
        XCTAssertEqual(wide.scanReference?.size.x,original.size.x)
        wide.family = .bed
        XCTAssertEqual(wide.size.x,3.5,"Style replacement retains chosen dimensions")
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
}

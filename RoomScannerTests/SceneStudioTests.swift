import XCTest
import SceneKit
import ModelIO
#if os(iOS)
import SwiftUI
import UIKit
#endif
@testable import RoomScanner

final class SceneStudioTests: XCTestCase {
    private func seed() -> SceneEditDocument {
        var house = HouseBuilder().build(from: SyntheticRooms.twoRoomApartment(),name: "Studio test")
        let object = PlacedObject(id: UUID(),category: "sofa",center: .init(x: 1,y: -1),size: .init(width: 2,depth: 0.9),height: 0.85,angle: 0.3,confidence: .high)
        house.stories[0].rooms[0].objects = [object]
        return .seed(house: house,source: .house,id: house.id)
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
        XCTAssertEqual(tabs.tabBar.items?.compactMap(\.title),["House","Technik","Capture","Profile","Settings"])
        let image = UIGraphicsImageRenderer(bounds: hosting.view.bounds).image { _ in hosting.view.drawHierarchy(in: hosting.view.bounds,afterScreenUpdates: true) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dwalk-five-tabs-"+UUID().uuidString+".png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("FIVE_TAB_LAYOUT="+url.path)
    }
    @MainActor func testPhoneStudioKeepsCanvasFullHeightWithInspectorClosed() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0,y: 0,width: 393,height: 852)
        let location = StorageLocation.temporary()
        let hosting = UIHostingController(rootView: NavigationStack {
            StudioEditorView(document: seed(),storageURL: location.documentsURL.appendingPathComponent("design.json"))
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dwalk-fullscreen-studio-"+UUID().uuidString+".png")
        try png.write(to: url); print("STUDIO_PHONE_LAYOUT="+url.path)
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

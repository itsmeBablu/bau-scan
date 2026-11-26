import XCTest
@testable import RoomScanner

final class PhotoArchiveTests: XCTestCase {
    func testRepeatedPhotosStayInSameRoomAndSeparateFloorsUseTheirOwnFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        var layout = PhotoArchiveLayout()
        let room = UUID()
        let first = image("Bath Room",number:1,roomID:room)
        let second = image("Bath Room",number:2,roomID:room)
        let lower = ScanOrganization(level:-1,buildingName:"A",kind:.house)
        let upper = ScanOrganization(level:1,buildingName:"A",kind:.house)
        let files = try SurveyPhotoArchiveWriter.write([first,second],to:root,used:&layout,sourceID:"source",organization:lower,locale:Locale(identifier:"de"))
        XCTAssertTrue(files[0].imageFile.hasPrefix("Photos/A/-1.UG 1/Bath Room/"))
        XCTAssertEqual(URL(fileURLWithPath:files[0].imageFile).deletingLastPathComponent(),URL(fileURLWithPath:files[1].imageFile).deletingLastPathComponent())
        let other = try SurveyPhotoArchiveWriter.write([image("Bath Room",number:1)],to:root,used:&layout,sourceID:"other",organization:upper,locale:Locale(identifier:"de"))
        XCTAssertTrue(other[0].imageFile.hasPrefix("Photos/A/1.1. OG/Bath Room/"))
    }
    private func image(_ room: String, number: Int,roomID:UUID = UUID()) -> SurveyPhotoImage {
        .init(photo:.init(id:UUID(),roomID:roomID,number:number,pose:[1,0,0,0,0,1,0,0,0,0,1,0,2,1,3,1],timestamp:3),jpegData:Data([0xff,0xd8,0xff,0xd9]),roomName:room)
    }
    func testPhotoFoldersUseRoomDotNumberWithoutCollisionsOrUnsafeWindowsNames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        var used = PhotoArchiveLayout()
        let records = try SurveyPhotoArchiveWriter.write([image("Küche",number:1),image("Bad",number:1),image("KÜCHE",number:1),image("../CON",number:2)],to:root,used:&used,locale:Locale(identifier:"en"))
        XCTAssertEqual(records[0].imageFile,"Photos/Unassigned building/Unassigned level/Küche/Küche.1.jpg")
        XCTAssertEqual(records[1].imageFile,"Photos/Unassigned building/Unassigned level/Bad/Bad.1.jpg")
        XCTAssertNotEqual(records[0].imageFile.lowercased(),records[2].imageFile.lowercased())
        for record in records {
            XCTAssertFalse(record.imageFile.contains("../"))
            XCTAssertTrue(FileManager.default.fileExists(atPath:root.appendingPathComponent(record.imageFile).path))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent(record.cameraFile))) as? [String:Any])
            XCTAssertEqual(json["deviceValidationPending"] as? Bool,true)
            XCTAssertEqual((json["rawCameraPose"] as? [Double])?[13],1)
        }
        XCTAssertEqual(ArchivePath.component("CON"),"_CON")
        XCTAssertEqual(ArchivePath.component("..."),"Room")
    }
    func testProjectBundleStagesOrganisedSourcesReportsAndPhotosWithoutRewritingScan() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let location = StorageLocation(kind:.local,documentsURL:root); try location.prepare()
        let scan = SyntheticRooms.rectangularRoom().scan
        let room = FloorPlanBuilder().build(from:scan,name:"Küche")
        var package = RoomPackage(record:RoomRecord(plan:room),plan:room,scan:scan)
        var photo = image("Küche",number:1); var record = photo.photo; record.roomID = room.id
        photo = .init(photo:record,jpegData:photo.jpegData,roomName:room.name)
        package.surveyPhotos = [record]; package.surveyPhotoAssets = [record.id:photo.jpegData]
        let source = location.packageURL(for:room.id); try package.write(to:source)
        let original = try Data(contentsOf:source.appendingPathComponent("plan.json"))
        let ref = ProjectReference(kind:.room,itemID:room.id,library:"local")
        let project = RenovationProject(name:"Flat",references:[ref])
        let index = ProjectIndex(projects:[project])
        let entry = ProjectLibraryEntry(reference:ref,title:room.name,date:Date(),area:12,roomCount:1,root:root,url:source)
        let output = root.appendingPathComponent("bundle")
        try await ProjectBundleExporter.files(project:project,index:index,entries:[entry],locale:Locale(identifier:"en_GB"),in:output)
        for path in ["Photos/Unassigned building/Unassigned level/Küche/Küche.1.jpg","Photos/Unassigned building/Unassigned level/Küche/Küche.1.camera.json","Reports/project-report.pdf","Quantities/quantities.csv","manifest.json","project-index.json"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath:output.appendingPathComponent(path).path),path)
        }
        let manifest = try JSONDecoder().decode(ProjectBundleExporter.Manifest.self,from:Data(contentsOf:output.appendingPathComponent("manifest.json")))
        XCTAssertEqual(manifest.photos.count,1)
        XCTAssertTrue(manifest.records.contains { $0.path.contains("/Original/") && $0.status == "exported" })
        XCTAssertEqual(try Data(contentsOf:source.appendingPathComponent("plan.json")),original)
    }
}

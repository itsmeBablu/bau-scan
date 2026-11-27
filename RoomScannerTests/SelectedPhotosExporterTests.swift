import XCTest
@testable import RoomScanner

final class SelectedPhotosExporterTests:XCTestCase {
    private let pose:[Double] = [1,0,0,0,0,1,0,0,0,0,1,0,2,1,3,1]
    private let bytes = Data([0xff,0xd8,0xff,0xd9])

    func testSelectionFoldersPreserveNumbersCameraPoseAndChecksums() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let reference = ProjectReference(kind:.house,itemID:UUID(),library:"local")
        let first = try asset(reference:reference,room:UUID(),number:1,name:"Bath Room",root:root.appendingPathComponent("source"))
        let second = try asset(reference:reference,room:UUID(),number:1,name:"Bath Room",root:first.root)
        let omitted = try asset(reference:reference,room:UUID(),number:2,name:"Kitchen",root:first.root)
        let project = RenovationProject(name:"A",references:[reference])
        let organization: [String:ScanOrganization] = [reference.id:.init(level:0,buildingName:"Building A",kind:.house)]
        let output = root.appendingPathComponent("export")
        try SelectedPhotosExporter.files(project:project,assets:[first,second],organization:organization,summaries:[:],locale:Locale(identifier:"de"),in:output)
        let records = try JSONDecoder().decode([SurveyPhotoArchiveWriter.Entry].self,from:Data(contentsOf:output.appendingPathComponent("photo-index.json")))
        XCTAssertEqual(Set(records.map(\.photoID)),[first.photo.id,second.photo.id])
        XCTAssertFalse(records.contains { $0.photoID == omitted.photo.id })
        let folders = Set(records.map { URL(fileURLWithPath:$0.imageFile).deletingLastPathComponent().lastPathComponent })
        XCTAssertEqual(folders,["Bath Room","Bath Room 2"])
        for record in records {
            XCTAssertTrue(record.imageFile.hasPrefix("Photos/Building A/0.EG/"))
            XCTAssertEqual(record.number,1)
            XCTAssertEqual(try Data(contentsOf:output.appendingPathComponent(record.imageFile)),bytes)
            let camera = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:output.appendingPathComponent(record.cameraFile))) as? [String:Any])
            XCTAssertEqual(camera["rawCameraPose"] as? [Double],pose)
            XCTAssertEqual(camera["deviceValidationPending"] as? Bool,true)
        }
        try ExportManifestValidation.validate(in:output)
        XCTAssertEqual(try first.image().jpegData,bytes)
        try Data("tampered".utf8).write(to:output.appendingPathComponent(records[0].imageFile),options:.atomic)
        XCTAssertThrowsError(try ExportManifestValidation.validate(in:output))
    }

    func testLegacyUnassignedAndUnsafeNamesStayWithinExportAndNeverOverwrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let reference = ProjectReference(kind:.technicalRoom,itemID:UUID(),library:"local")
        let photo = try asset(reference:reference,room:UUID(),number:7,name:"../CON:Room",root:root.appendingPathComponent("source"))
        let project = RenovationProject(name:"A",references:[reference]),output = root.appendingPathComponent("export")
        try SelectedPhotosExporter.files(project:project,assets:[photo],organization:[:],summaries:[:],locale:Locale(identifier:"en"),in:output)
        let records = try JSONDecoder().decode([SurveyPhotoArchiveWriter.Entry].self,from:Data(contentsOf:output.appendingPathComponent("photo-index.json")))
        XCTAssertTrue(records[0].imageFile.hasPrefix("Photos/Unassigned building/Unassigned level/"))
        XCTAssertFalse(records[0].imageFile.split(separator:"/").contains(".."))
        XCTAssertFalse(records[0].imageFile.contains(":"))
        XCTAssertEqual(records[0].number,7)
        let index = try Data(contentsOf:output.appendingPathComponent("photo-index.json"))
        XCTAssertThrowsError(try SelectedPhotosExporter.files(project:project,assets:[photo],organization:[:],summaries:[:],locale:Locale(identifier:"en"),in:output))
        XCTAssertEqual(try Data(contentsOf:output.appendingPathComponent("photo-index.json")),index)
        XCTAssertThrowsError(try SelectedPhotosExporter.files(project:RenovationProject(name:"Other"),assets:[photo],organization:[:],summaries:[:],locale:Locale(identifier:"en"),in:root.appendingPathComponent("foreign")))
        XCTAssertThrowsError(try SelectedPhotosExporter.export(project:project,assets:[photo],organization:[:],summaries:[:],locale:Locale(identifier:"en"),to:root.appendingPathComponent("wrong.pdf")))
    }

    func testCustomFloorNameChangesOnlyExportFolderLabel() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let reference = ProjectReference(kind:.house,itemID:UUID(),library:"local")
        let photo = try asset(reference:reference,room:UUID(),number:7,name:"Office",root:root.appendingPathComponent("source"))
        var project = RenovationProject(name:"A",references:[reference]); project.details = .init(floorNames:[1:"Workplace"])
        let output = root.appendingPathComponent("export")
        try SelectedPhotosExporter.files(project:project,assets:[photo],organization:[reference.id:.init(level:1,kind:.house)],summaries:[:],locale:Locale(identifier:"en"),in:output)
        let records = try JSONDecoder().decode([SurveyPhotoArchiveWriter.Entry].self,from:Data(contentsOf:output.appendingPathComponent("photo-index.json")))
        XCTAssertTrue(records[0].imageFile.contains("/1.Workplace/"))
        XCTAssertEqual(records[0].photoID,photo.photo.id); XCTAssertEqual(records[0].number,7)
        XCTAssertEqual(try photo.image().jpegData,bytes)
    }

    private func asset(reference:ProjectReference,room:UUID,number:Int,name:String,root:URL) throws -> ProjectPhotoAsset {
        let photo = SurveyPhoto(id:UUID(),roomID:room,number:number,pose:pose,timestamp:3)
        let target = root.appendingPathComponent(photo.jpegPath)
        try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
        try bytes.write(to:target)
        return .init(reference:reference,photo:photo,roomName:name,root:root,relativePath:photo.jpegPath)
    }
}

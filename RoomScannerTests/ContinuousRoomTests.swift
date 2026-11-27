import XCTest
import simd
@testable import RoomScanner

final class ContinuousRoomTests:XCTestCase {
    func testOutsidePinDisplayStaysInsideRoomWithoutChangingObservation() {
        let room = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"Room")
        let original = TechnicalPoint3(x:100,y:100,z:100)
        let shown = ScanNoteRegistration.contained(original,in:room)
        XCTAssertTrue(Polygon2D.contains(room.floorPolygon,.init(x:shown.x,y:-shown.z)))
        XCTAssertLessThan(shown.y,room.ceilingHeight.upperBound)
        XCTAssertEqual(original.x,100)
    }
    private func scan(partitionLength:Float) -> ScanInput {
        var scan = SyntheticRooms.rectangularRoom(origin:.zero,width:4,depth:3)
        if let floor = scan.surfaces.firstIndex(where:{ $0.category == .floor }) {
            scan.surfaces[floor].polygonCorners = [SIMD3(-2,0,1.5),SIMD3(2,0,1.5),SIMD3(2,0,-1.5),SIMD3(-2,0,-1.5)]
        }
        scan.surfaces.append(ScanSurface(category:.wall,dimensions:SIMD3(partitionLength,2.5,0),transform:.roomPlacement(x:2,y:1.25,z:-1.5,yaw:.pi/2)))
        scan.sections = [.init(label:.kitchen,center:SIMD3(1,0,-1.5)),.init(label:.bedroom,center:SIMD3(3,0,-1.5))]
        return scan
    }
    func testContinuousCaptureUsesObservedPartitionAndSpatialRoomNames() throws {
        let capture = scan(partitionLength:3)
        let house = try HouseBuilder().build(from:.init(rooms:[capture]),name:"House")
        XCTAssertEqual(house.allRooms.count,2)
        XCTAssertEqual(house.allRooms.map(\.label),[.kitchen,.bedroom])
        for room in house.allRooms { XCTAssertEqual(RoomMeasurements(plan:room).floorArea,6,accuracy:0.001) }
        XCTAssertEqual(Set(house.allRooms.map(\.id)).count,2)
        XCTAssertTrue(house.allRooms.allSatisfy { $0.sourceCaptureID == capture.id })
        let reopened = try HouseBuilder().build(from:.init(rooms:[capture]),name:"House")
        XCTAssertEqual(house.allRooms.map(\.id),reopened.allRooms.map(\.id))
        XCTAssertEqual(ProjectScanSummary(house:house).rooms,2)
    }
    func testPartialWallAndOpenPlanLabelsDoNotInventSeparateRooms() throws {
        let house = try HouseBuilder().build(from:.init(rooms:[scan(partitionLength:1)]),name:"House")
        XCTAssertEqual(house.allRooms.count,1)
        XCTAssertEqual(RoomMeasurements(plan:house.allRooms[0]).floorArea,12,accuracy:0.001)
    }
    func testOldScanWithoutSpatialSectionsStillDecodes() throws {
        let original = SyntheticRooms.rectangularRoom().scan
        let decoded = try JSONDecoder().decode(ScanInput.self,from:JSONEncoder().encode(original))
        XCTAssertNil(decoded.sections)
        XCTAssertEqual(decoded,original)
    }
    func testUnmeasuredWallsUseSlimDisplayThickness() {
        let plan = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"Room")
        let graph = HouseWallGraph(house:House(room:plan))
        XCTAssertTrue(graph.walls.allSatisfy { $0.thickness == 0.10 && $0.thicknessSource == .defaultValue })
    }
    func testNoteUsesItsPhysicalRoomAndPreservesCameraHeight() throws {
        let capture = scan(partitionLength:3)
        let house = try HouseBuilder().build(from:.init(rooms:[capture]),name:"House")
        var note = ARNote(projectID:UUID(),reference:.init(kind:.house,itemID:house.id,library:"local"),number:1,level:0,roomID:capture.id,position:.init(x:3,y:0,z:-1.5),planPosition:nil,language:"en")
        note.cameraPosition = .init(x:3,y:1.4,z:-1)
        note.audioFileName = "note.m4a"
        let registered = try XCTUnwrap(ScanNoteRegistration.registered([note],house:house,scans:[capture],singleRoom:false).first)
        XCTAssertEqual(registered.roomID,house.allRooms[1].id)
        XCTAssertEqual(AnnotationPresentation.noteIconPosition(registered,anchor:try XCTUnwrap(registered.viewingPosition)).y,1.4,accuracy:0.001)
        let title = VoiceNoteDisplayName.title(note,summary:ProjectScanSummary(house:house),locale:Locale(identifier:"en"))
        XCTAssertTrue(title.hasPrefix(house.allRooms[1].name+" · "))
        XCTAssertTrue(title.contains("6")); XCTAssertTrue(title.hasSuffix(" · 1"))
        var renamed = note; renamed.title = "Heating check"
        XCTAssertEqual(VoiceNoteDisplayName.title(renamed,summary:ProjectScanSummary(house:house),locale:Locale(identifier:"en")),"Heating check")
    }
    func testPhotoAlbumsSeparateFloorsAndKeepRoomIdentityScopedToScan() throws {
        let house = try HouseBuilder().build(from:SyntheticRooms.twoStoryHouse(),name:"House")
        let ref = ProjectReference(kind:.house,itemID:house.id,library:"local")
        let assets = house.allRooms.enumerated().map { index,room in
            ProjectPhotoAsset(reference:ref,photo:SurveyPhoto(id:UUID(),roomID:room.id,number:index+1,pose:[1,0,0,0,0,1,0,0,0,0,1,0,0,1.4,0,1],timestamp:1),roomName:room.name,root:URL(fileURLWithPath:"/tmp/photos"),relativePath:"photo.jpg")
        }
        let floors = PhotoAlbumGrouping.floors(assets,summaries:[ref.id:ProjectScanSummary(house:house)],organization:[:],locale:Locale(identifier:"en"))
        let renamed = PhotoAlbumGrouping.floors(assets,summaries:[ref.id:ProjectScanSummary(house:house)],organization:[:],locale:Locale(identifier:"en"),floorNames:[0:"Entrance",1:"Office"])
        XCTAssertTrue(renamed.contains { $0.name == "Entrance" })
        XCTAssertEqual(Set(renamed.flatMap(\.photos).map(\.id)),Set(assets.map(\.id)))
        XCTAssertEqual(floors.count,2)
        XCTAssertEqual(floors.flatMap(\.rooms).count,house.allRooms.count)
        XCTAssertEqual(Set(floors.flatMap(\.photos).map(\.id)),Set(assets.map(\.id)))
    }
}

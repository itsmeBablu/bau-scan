import XCTest
@testable import RoomScanner

final class ScanSessionIntegrationTests:XCTestCase {
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    func testVoiceEvidenceRecoversEvenWithoutRoomGeometry() async throws {
        let root = root(),documents = self.root()
        defer { try? FileManager.default.removeItem(at:root); try? FileManager.default.removeItem(at:documents) }
        let disk = ScanSessionStore(root:root),project = UUID()
        let organization = ScanOrganization(level:-1,buildingName:"A",zoneName:"Kitchen",number:1,kind:.house)
        let session = try await disk.create(kind:.house,projectID:project,organization:organization)
        let reference = ProjectReference(kind:.house,itemID:session.id,library:"local")
        var note = ARNote(projectID:project,reference:reference,number:1,level:0,roomID:nil,position:.init(x:1,y:2,z:3),planPosition:nil,language:"en")
        note.audioFileName = note.stem+".m4a"; note.audioDuration = 1
        let bytes = Data([0,0,0,16])+Data("ftypM4A ".utf8)
        let media = ScanVoiceMedia(note:note,audio:bytes,pose:nil,capturedAt:Date())
        try await disk.write(session.id,key:"voice-"+note.id.uuidString,data:JSONEncoder().encode(media),media:true)
        do { _ = try await ScanSessionRecovery().promote(session,store:disk,documents:documents); XCTFail("Geometry should remain unavailable") }
        catch { XCTAssertTrue(error is ScanSessionRecovery.MissingGeometry) }
        XCTAssertEqual(try ARNoteStore.read(root:documents,projectID:project).audio[note.id],bytes)
        let state = try await disk.read(session.id); XCTAssertEqual(state.state,.failed)
        XCTAssertEqual(try ProjectIndexStore.read(root:documents).projects.first(where:{ $0.id == project })?.references,[reference])
    }
    func testLatestRoomSnapshotOverwritesRatherThanAppendingDuplicates() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at:root) }
        let disk = ScanSessionStore(root:root),session = try await disk.create(kind:.room,projectID:nil)
        for i in 0..<8 { try await disk.writeLatest(session.id,key:"room-stable",data:Data([UInt8(i)])) }
        let values = try await disk.latestValues(session.id,prefix:"room-")
        XCTAssertEqual(values.count,1); XCTAssertEqual(values.first?.data,Data([7]))
        let entries = try await disk.entries(session.id); XCTAssertTrue(entries.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent(session.id.uuidString+"/latest"),includingPropertiesForKeys:nil)
        XCTAssertEqual(files.count,1)
    }
    func testPartialHouseRecoveryIsIdempotentAndPreservesFinalLibraryFile() async throws {
        let root = root(),documents = self.root()
        defer { try? FileManager.default.removeItem(at:root); try? FileManager.default.removeItem(at:documents) }
        let disk = ScanSessionStore(root:root),project = UUID()
        let session = try await disk.create(kind:.house,projectID:project)
        let scan = SyntheticRooms.rectangularRoom(origin:.zero,width:4,depth:3)
        let saved = PersistedRoom(scan:scan,raw:Data("opaque native capture".utf8),partial:true)
        try await disk.writeLatest(session.id,key:"room-"+scan.id.uuidString,data:JSONEncoder().encode(saved))
        let service = ScanSessionRecovery()
        let first = try await service.promote(session,store:disk,documents:documents)
        let target = StorageLocation(kind:.local,documentsURL:documents).housePackageURL(for:session.id)
        XCTAssertTrue(try HousePackage.readRecord(from:target).incomplete == true)
        let original = try Data(contentsOf:target.appendingPathComponent("house.json"))
        let second = try await service.promote(session,store:disk,documents:documents)
        XCTAssertEqual(first,second); XCTAssertEqual(try Data(contentsOf:target.appendingPathComponent("house.json")),original)
        let index = try ProjectIndexStore.read(root:documents)
        XCTAssertEqual(index.projects.first(where:{ $0.id == project })?.references,[first])
        XCTAssertEqual(index.scanOrganization?[first.id],organization)
        let state = try await disk.read(session.id); XCTAssertEqual(state.state,.completed)
    }
    func testFailedPromotionKeepsDraftAndExistingLibraryBytes() async throws {
        let root = root(),documents = self.root()
        defer { try? FileManager.default.removeItem(at:root); try? FileManager.default.removeItem(at:documents) }
        let disk = ScanSessionStore(root:root),session = try await disk.create(kind:.house,projectID:nil)
        do { _ = try await ScanSessionRecovery().promote(session,store:disk,documents:documents); XCTFail() } catch {}
        let state = try await disk.read(session.id); XCTAssertEqual(state.state,.failed)
        let unfinished = try await disk.unfinished(); XCTAssertEqual(unfinished.count,1)
    }
    func testMeshDeltaWritesOnlyChangedAnchorsAndReplaysRemovals() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at:root) }
        let disk = ScanSessionStore(root:root),session = try await disk.create(kind:.technical,projectID:nil)
        let writer = TechnicalSessionDeltaWriter(),a = UUID(),b = UUID()
        func patch(_ id:UUID,_ height:Double) -> TechnicalMeshSnapshot.Patch {
            .init(anchorID:id,vertices:[.init(x:0,y:0,z:0),.init(x:1,y:0,z:0),.init(x:0,y:height,z:0)],triangleIndices:[0,1,2])
        }
        func snapshot(_ time:Double,_ values:[TechnicalMeshSnapshot.Patch]) -> TechnicalMeshSnapshot {
            .init(timestamp:time,patches:values,alignmentVerified:false,truncated:false)
        }
        _ = try await writer.append(snapshot:snapshot(1,[patch(a,1),patch(b,1)]),active:[a,b],journal:.init(),store:disk,id:session.id)
        let unchanged = try await writer.append(snapshot:snapshot(2,[patch(a,1),patch(b,1)]),active:[a,b],journal:.init(),store:disk,id:session.id)
        XCTAssertEqual(unchanged,0)
        _ = try await writer.append(snapshot:snapshot(3,[patch(a,2),patch(b,1)]),active:[a],journal:.init(),store:disk,id:session.id)
        let entries = try await disk.entries(session.id); XCTAssertEqual(entries.count,2)
        let delta = try JSONDecoder().decode(TechnicalSessionDelta.self,from:await disk.payload(session.id,entry:entries[1]))
        XCTAssertEqual(delta.changed.map(\.anchorID),[a]); XCTAssertEqual(delta.removed,[b])
        let recovered = try await TechnicalSessionDeltaWriter.recover(store:disk,id:session.id)
        XCTAssertEqual(recovered.meshes.last?.patches,[patch(a,2)])
    }
    func testMediaIsOnDiskImmediatelyAndKeepsRoomAndPose() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at:root) }
        let disk = ScanSessionStore(root:root),session = try await disk.create(kind:.house,projectID:nil),room = UUID()
        let pose:[Double] = [1,0,0,0,0,1,0,0,0,0,1,0,1,2,3,1]
        let value = ScanPhotoMedia(photo:.init(id:UUID(),roomID:room,number:1,pose:pose,timestamp:10,capturedAt:Date()),jpeg:Data([0xff,0xd8,0xff,0xd9]))
        try await disk.write(session.id,key:"photo",data:JSONEncoder().encode(value),media:true)
        let reopened = ScanSessionStore(root:root)
        let loaded = try await reopened.latest(session.id,key:"photo")
        let bytes = try XCTUnwrap(loaded)
        let restored = try JSONDecoder().decode(ScanPhotoMedia.self,from:bytes)
        XCTAssertEqual(restored.photo.roomID,room); XCTAssertEqual(restored.photo.pose,pose); XCTAssertEqual(restored.jpeg,value.jpeg)
    }
    func testTechnicalRecoveryCompactsDeltasAndPreservesSurveyIdentity() async throws {
        let root = root(),documents = self.root()
        defer { try? FileManager.default.removeItem(at:root); try? FileManager.default.removeItem(at:documents) }
        let disk = ScanSessionStore(root:root),session = try await disk.create(kind:.technical,projectID:nil)
        let patch = TechnicalMeshSnapshot.Patch(anchorID:UUID(),vertices:[.init(x:0,y:0,z:0),.init(x:1,y:0,z:0),.init(x:0,y:1,z:0)],triangleIndices:[0,1,2])
        _ = try await TechnicalSessionDeltaWriter().append(snapshot:.init(timestamp:1,patches:[patch],alignmentVerified:false,truncated:false),active:[patch.anchorID],journal:.init(),store:disk,id:session.id)
        let reference = try await ScanSessionRecovery().promote(session,store:disk,documents:documents)
        let package = try TechnicalRoomPackage.read(from:documents.appendingPathComponent("TechnicalRooms/\(session.id.uuidString).technicalroom"))
        XCTAssertEqual(package.manifest.id,session.id); XCTAssertEqual(package.document.room.id,session.id)
        XCTAssertEqual(reference.kind,.technicalRoom); XCTAssertTrue(package.manifest.incomplete == true)
        XCTAssertEqual(package.journal.meshes.last?.patches,[patch])
    }
    func testAudioEnvelopeCommitsWithItsReferenceAndPoseBeforeRecovery() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at:root) }
        let disk = ScanSessionStore(root:root),session = try await disk.create(kind:.house,projectID:UUID())
        let room = UUID(),reference = ProjectReference(kind:.house,itemID:session.id,library:"local")
        var note = ARNote(projectID:session.projectID!,reference:reference,number:1,level:1,roomID:room,position:.init(x:1,y:2,z:3),planPosition:nil,language:"de-DE")
        note.audioFileName = note.stem+".m4a"; note.audioDuration = 1
        let value = ScanVoiceMedia(note:note,audio:Data([1,2,3]),pose:[1,0,0,0,0,1,0,0,0,0,1,0,1,2,3,1],capturedAt:Date())
        try await disk.write(session.id,key:"voice-"+note.id.uuidString,data:JSONEncoder().encode(value),media:true)
        let entries = try await disk.entries(session.id)
        let restored = try JSONDecoder().decode(ScanVoiceMedia.self,from:await disk.payload(session.id,entry:entries[0]))
        XCTAssertEqual(restored.note.reference,reference); XCTAssertEqual(restored.note.roomID,room)
        XCTAssertEqual(restored.note.level,1); XCTAssertEqual(restored.pose,value.pose); XCTAssertEqual(restored.audio,value.audio)
    }
    func testJournalDeltaHandlesChangedTimestampOriginWithoutDuplicatingFrames() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at:root) }
        let disk = ScanSessionStore(root:root),session = try await disk.create(kind:.technical,projectID:nil)
        let writer = TechnicalSessionDeltaWriter()
        var journal = TechnicalCaptureJournal()
        let pose:[Double] = [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
        func frame(_ time:Double) -> TechnicalFrameRecord {
            .init(timestamp:time,cameraTransform:pose,intrinsics:[1,0,0,0,1,0,0,0,1],imageWidth:1,imageHeight:1,tracking:"normal",hasSceneDepth:true,hasSmoothedSceneDepth:false,alignmentVerified:false)
        }
        journal.append(frame(1000))
        _ = try await writer.append(snapshot:.init(timestamp:1000,patches:[],alignmentVerified:false,truncated:false),active:[],journal:journal,store:disk,id:session.id)
        journal.append(frame(10))
        _ = try await writer.append(snapshot:.init(timestamp:10,patches:[],alignmentVerified:false,truncated:false),active:[],journal:journal,store:disk,id:session.id)
        let unchanged = try await writer.append(snapshot:.init(timestamp:11,patches:[],alignmentVerified:false,truncated:false),active:[],journal:journal,store:disk,id:session.id)
        XCTAssertEqual(unchanged,0)
        let recovered = try await TechnicalSessionDeltaWriter.recover(store:disk,id:session.id)
        XCTAssertEqual(recovered.frames.map(\.timestamp),[1000,10])
    }
    func testDisjointConvexClippingDoesNotFragmentLargeFloor() {
        let subject:[Point2D] = [.init(x:0,y:0),.init(x:20,y:0),.init(x:20,y:20),.init(x:0,y:20)]
        let clip:[Point2D] = [.init(x:21,y:0),.init(x:22,y:0),.init(x:22,y:20),.init(x:21,y:20)]
        XCTAssertEqual(WallJunctions.subtract(subject,convex:clip),[subject])
    }
}

import XCTest
import RealityKit
@testable import RoomScanner

final class AnnotationIconTests:XCTestCase {
    @MainActor func testMarkerHasTapVolumeAndStableIdentifier() {
        let marker = AnnotationIcon.entity(symbol:"mic.fill",name:"scan-note:test")
        XCTAssertEqual(marker.name,"scan-note:test")
        XCTAssertNotNil(marker.components[InputTargetComponent.self])
        XCTAssertNotNil(marker.components[BillboardComponent.self])
        XCTAssertEqual(marker.components[CollisionComponent.self]?.shapes.count,1)
    }
    @MainActor func testPhotoKeepsDirectionFrustumAndVoiceKeepsCameraLeader() throws {
        let photo = SurveyPhoto(id:UUID(),number:1,pose:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],timestamp:1)
        let camera = SurveyPhotoMarkers.entity(photo)
        XCTAssertEqual(camera.children.filter { $0.name.hasPrefix("photo-frustum-") }.count,8)
        var note = ARNote(projectID:UUID(),reference:.init(kind:.house,itemID:UUID(),library:"local"),number:1,level:0,roomID:nil,position:.init(x:1,y:1,z:1),planPosition:nil,language:"en")
        note.cameraPosition = .init(x:0,y:1.5,z:0); note.audioFileName = "note-01.m4a"; note.audioDuration = 1
        let marker = AnnotationIcon.noteEntity(note)
        XCTAssertNotNil(marker.findEntity(named:"capture-to-pin"))
        XCTAssertNotNil(marker.findEntity(named:"pin-label-leader"))
        let voice = try XCTUnwrap(marker.findEntity(named:"scan-note:"+note.id.uuidString))
        XCTAssertGreaterThan(voice.position.y,0,"Voice icon floats above its spatial anchor")
    }

}

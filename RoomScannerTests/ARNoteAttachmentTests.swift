import XCTest
@testable import RoomScanner

final class ARNoteAttachmentTests:XCTestCase {
    func testClosestTextPinWinsAndVoiceClipsAreNotReusedAsPins() throws {
        let ref = ProjectReference(kind:.house,itemID:UUID(),library:"local"),owner = UUID()
        let pin = ARNote(projectID:owner,reference:ref,number:1,level:0,roomID:nil,position:.init(x:1,y:1,z:1),planPosition:nil,language:"en")
        var voice = pin; voice.id = UUID(); voice.anchorPinID = pin.id; voice.position = .init(x:1.1,y:1,z:1)
        voice.audioFileName = "note-01.m4a"; voice.audioDuration = 1
        XCTAssertEqual(ARNoteAttachment.nearest(to:.init(x:1.1,y:1,z:1),in:[voice,pin])?.id,pin.id)
        XCTAssertNil(ARNoteAttachment.nearest(to:.init(x:3,y:1,z:1),in:[pin]))
        voice.cameraPosition = .init(x:0,y:1.5,z:0)
        let restored = try JSONDecoder().decode(ARNote.self,from:JSONEncoder().encode(voice))
        XCTAssertEqual(restored.anchorPinID,pin.id); XCTAssertEqual(restored.cameraPosition,voice.cameraPosition)
        XCTAssertNotEqual(restored.id,pin.id,"A new voice clip must not overwrite the anchor pin")
    }
}

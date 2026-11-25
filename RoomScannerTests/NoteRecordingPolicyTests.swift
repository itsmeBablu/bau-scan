import XCTest
@testable import RoomScanner

final class NoteRecordingPolicyTests: XCTestCase {
    func testShortCancelledAndInvalidClipsAreNotSaved() {
        for (seconds,cancelled,keep) in [(0.49,false,false),(0.5,false,true),(60.0,false,true),(12.0,true,false),(.infinity,false,false),(.nan,false,false)] {
            XCTAssertEqual(NoteRecordingPolicy.action(seconds:seconds,cancelled:cancelled),keep)
        }
        XCTAssertTrue(NoteRecordingPolicy.gesture(x:-80,y:0).cancel)
        XCTAssertTrue(NoteRecordingPolicy.gesture(x:0,y:-80).lock)
        XCTAssertFalse(NoteRecordingPolicy.gesture(x:-20,y:-20).lock)
    }
}

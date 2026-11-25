import XCTest
@testable import RoomScanner
final class RecorderEventPolicyTests:XCTestCase {
    func testRouteReasonsAndGracePeriod() {
        for reason:UInt in [0,1,3,4,6,8] { XCTAssertNil(RecorderEventPolicy.stopReason(.route(reason,inputLost:true),sinceActivation:1)) }
        for reason:UInt in [2,7] {
            XCTAssertNil(RecorderEventPolicy.stopReason(.route(reason,inputLost:true),sinceActivation:0.499))
            XCTAssertNotNil(RecorderEventPolicy.stopReason(.route(reason,inputLost:true),sinceActivation:0.5))
        }
        XCTAssertNil(RecorderEventPolicy.stopReason(.route(2,inputLost:false),sinceActivation:1))
        XCTAssertNil(RecorderEventPolicy.stopReason(.interruption(0),sinceActivation:1))
        XCTAssertNil(RecorderEventPolicy.stopReason(.interruption(nil),sinceActivation:1))
        for event in [RecorderEventPolicy.Event.interruption(1),.mediaReset,.background] { XCTAssertNotNil(RecorderEventPolicy.stopReason(event,sinceActivation:0)) }
    }
    func testFakeRecorderDoesNotSelfStopOnActivationAndRejectsLatePermission() {
        struct FakeRecorder {
            var state = RecorderStateMachine()
            mutating func event(_ event:RecorderEventPolicy.Event,_ elapsed:Double) {
                if RecorderEventPolicy.stopReason(event,sinceActivation:elapsed) != nil { state.stop() }
            }
        }
        var fake = FakeRecorder()
        let request = fake.state.prepare()
        fake.event(.route(3,inputLost:false),0)
        XCTAssertTrue(fake.state.started(request))
        XCTAssertEqual(fake.state.phase,.recording)
        fake.event(.interruption(0),1); XCTAssertEqual(fake.state.phase,.recording)
        fake.event(.route(2,inputLost:true),1); XCTAssertEqual(fake.state.phase,.idle)
        let stale = fake.state.prepare(); fake.state.stop()
        XCTAssertFalse(fake.state.started(stale))
        XCTAssertTrue(fake.state.started(fake.state.prepare()))
    }
}

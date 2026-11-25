import XCTest
@testable import RoomScanner

final class DesignRefTests: XCTestCase {
    func testIdentityEqualityAndHashing() {
        let plan = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"Room")
        let document = SceneEditDocument(source:.room,sourceID:plan.id,title:"Design",shell:House(room:plan),objects:[])
        let date = Date(timeIntervalSince1970:100)
        let a = DesignRef(document,modifiedAt:date),b = DesignRef(document,modifiedAt:date)
        XCTAssertEqual(a,b); XCTAssertEqual(Set([a,b]).count,1)
        var changed = document; changed.source = .house
        XCTAssertNotEqual(a,DesignRef(changed,modifiedAt:date))
        XCTAssertNotEqual(a,DesignRef(document,modifiedAt:date.addingTimeInterval(1)))
    }
}

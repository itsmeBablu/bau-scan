import XCTest
@testable import RoomScanner

final class ProjectPreferenceResolutionTests:XCTestCase {
    func testAbsentAndUnknownValuesUseExplicitAppDefaults() {
        let appLocale = Locale(identifier:"en_GB")
        XCTAssertEqual(ProjectPreferenceResolution.locale(nil,appDefault:appLocale),appLocale)
        XCTAssertEqual(ProjectPreferenceResolution.unit(nil,appDefault:.millimeters),.millimeters)
        XCTAssertFalse(ProjectPreferenceResolution.photos(nil,appDefault:false))
        let unknown = ProjectPreferences(language:"unknown",units:"cm")
        XCTAssertEqual(ProjectPreferenceResolution.locale(unknown,appDefault:appLocale),appLocale)
        XCTAssertEqual(ProjectPreferenceResolution.unit(unknown,appDefault:.both),.both)
        XCTAssertEqual(ProjectPreferenceResolution.locale(.init(language:""),appDefault:appLocale),appLocale)
    }
    func testProjectOverridesRemainIndependentAndDoNotModifyTheirInputs() {
        let a = ProjectPreferences(language:"de",units:"mm",photos:false)
        let b = ProjectPreferences(language:"en",units:"m",photos:true)
        let appLocale = Locale(identifier:"en_GB")
        XCTAssertEqual(ProjectPreferenceResolution.locale(a,appDefault:appLocale).identifier,"de_DE")
        XCTAssertEqual(ProjectPreferenceResolution.locale(b,appDefault:appLocale).identifier,"en_GB")
        XCTAssertEqual(ProjectPreferenceResolution.unit(a,appDefault:.both),.millimeters)
        XCTAssertEqual(ProjectPreferenceResolution.unit(b,appDefault:.both),.meters)
        XCTAssertFalse(ProjectPreferenceResolution.photos(a,appDefault:true))
        XCTAssertTrue(ProjectPreferenceResolution.photos(b,appDefault:false))
        XCTAssertEqual(a.units,"mm"); XCTAssertEqual(b.units,"m")
        XCTAssertEqual(ProjectPreferenceResolution.locale(.init(language:"system"),appDefault:appLocale),Locale.current)
        XCTAssertEqual(ProjectPreferenceResolution.unit(nil,appDefault:.both),.both)
    }
}

import XCTest
@testable import RoomScanner

final class LocalizationCoverageTests: XCTestCase {
    func testEveryCatalogueKeyHasGermanTextAndMatchingFormatArguments() throws {
        let file = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RoomScanner/Resources/Localizable.xcstrings")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
        let strings = try XCTUnwrap(root["strings"] as? [String:[String:Any]])
        let expression = try NSRegularExpression(pattern:"%(?:[0-9]+\\$)?(?:lld|ld|d|@|f)")
        func tokens(_ text: String) -> [String] {
            expression.matches(in:text,range:NSRange(text.startIndex...,in:text)).map {
                let token = (text as NSString).substring(with:$0.range)
                return token.replacingOccurrences(of:"[0-9]+\\$",with:"",options:.regularExpression)
            }.sorted()
        }
        for (key, entry) in strings {
            let localizations = entry["localizations"] as? [String:[String:Any]]
            let german = (localizations?["de"]?["stringUnit"] as? [String:String])?["value"]
            let english = (localizations?["en"]?["stringUnit"] as? [String:String])?["value"] ?? key
            XCTAssertFalse((german ?? "").isEmpty,"Missing German: \(key)")
            XCTAssertEqual(tokens(german ?? ""),tokens(english),"Format mismatch: \(key)")
        }
    }
    func testGermanNumberFormatting() {
        XCTAssertTrue(MeasurementFormat.meters(1.25,locale:Locale(identifier:"de_DE")).contains("1,25"))
    }
}

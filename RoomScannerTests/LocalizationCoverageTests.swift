import XCTest
@testable import RoomScanner

final class LocalizationCoverageTests: XCTestCase {
    func testEveryCatalogueKeyHasGermanTextAndMatchingFormatArguments() throws {
        // Validate shipped resources; source-path reads can block on Desktop
        // privacy prompts. The Node audit separately validates the source catalogue.
        func strings(_ language:String) throws -> [String:String] {
            let url = try XCTUnwrap(Bundle.main.url(forResource:"Localizable",withExtension:"strings",subdirectory:nil,localization:language))
            let data = try Data(contentsOf:url)
            return try XCTUnwrap(PropertyListSerialization.propertyList(from:data,format:nil) as? [String:String])
        }
        let english = try strings("en"),german = try strings("de")
        XCTAssertFalse(english.isEmpty)
        let expression = try NSRegularExpression(pattern:"%(?:[0-9]+\\$)?(?:lld|ld|d|@|f)")
        func tokens(_ text: String) -> [String] {
            expression.matches(in:text,range:NSRange(text.startIndex...,in:text)).map {
                let token = (text as NSString).substring(with:$0.range)
                return token.replacingOccurrences(of:"[0-9]+\\$",with:"",options:.regularExpression)
            }.sorted()
        }
        for (key, value) in english {
            XCTAssertFalse((german[key] ?? "").isEmpty,"Missing German: \(key)")
            XCTAssertEqual(tokens(german[key] ?? ""),tokens(value),"Format mismatch: \(key)")
        }
    }
    func testGermanNumberFormatting() {
        XCTAssertTrue(MeasurementFormat.meters(1.25,locale:Locale(identifier:"de_DE")).contains("1,25"))
    }
}

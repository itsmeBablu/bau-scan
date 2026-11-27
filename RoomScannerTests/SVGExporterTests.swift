import XCTest
@testable import RoomScanner

final class SVGExporterTests: XCTestCase {
    func testUnnamedRoomLabelAndAreaUseTheRequestedLocaleWithoutChangingTheScan() {
        var plan = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:" \n")
        plan.label = .unidentified
        let original = plan
        let german = SVGExporter(locale:Locale(identifier:"de_DE")).svg(for:House(room:plan))
        XCTAssertTrue(german.contains(">Raum</text>"))
        XCTAssertTrue(german.contains(MeasurementFormat.squareMeters(Polygon2D.area(plan.floorPolygon),locale:Locale(identifier:"de_DE"))))
        XCTAssertTrue(SVGExporter(locale:Locale(identifier:"en_GB")).svg(for:House(room:plan)).contains(">Room</text>"))
        XCTAssertEqual(plan,original)
        plan.floorPolygon = []
        XCTAssertTrue(SVGExporter(locale:Locale(identifier:"de_DE")).svg(for:House(room:plan)).contains("Fläche nicht verfügbar"))
    }

    private var house: House { House(room: FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Salon")) }

    func testIsWellFormedXML() {
        let data = SVGExporter(locale: Locale(identifier: "fr_FR")).data(for: house)
        let parser = XMLParser(data: data)
        XCTAssertTrue(parser.parse(), "XML invalide : \(parser.parserError?.localizedDescription ?? "")")
    }

    func testMillimetreViewBoxMatchesBounds() throws {
        let svg = SVGExporter().svg(for: house)
        // 4 m × 3 m + 2 × 0.6 m de marge → 5200 × 4200 mm.
        XCTAssertTrue(svg.contains("width=\"5200mm\" height=\"4200mm\""), svg.prefix(300).description)
        XCTAssertTrue(svg.contains("viewBox=\"0 0 5200 4200\""))
    }

    func testLayersAndEntities() {
        let svg = SVGExporter(locale: Locale(identifier: "en_US")).svg(for: house)
        for id in ["floors", "walls", "doors", "windows", "openings", "objects", "dimensions", "text"] {
            XCTAssertTrue(svg.contains("<g id=\"\(id)\">"), id)
        }
        XCTAssertEqual(svg.components(separatedBy: "stroke-dasharray=\"50 40\"").count - 1, 1, "un arc de porte")
        XCTAssertGreaterThan(svg.components(separatedBy: "<polygon ").count - 1, 2, "floor, object and resolved wall footprints")
        XCTAssertTrue(svg.contains("4") && (svg.contains("mm") || svg.contains("m") || svg.contains("cm")), "cote du grand mur")
        XCTAssertTrue(svg.contains("Table"))
        XCTAssertTrue(svg.contains("Salon"), "nom de la pièce dans le calque text")
        XCTAssertTrue(svg.contains("m²"), "surface m² dans le calque text")
        XCTAssertTrue(svg.contains("BRH:"), "hauteur d'allège BRH de la fenêtre")
    }

    func testEmptyHouseProducesValidDocument() {
        let empty = House(name: "Vide", stories: [])
        XCTAssertTrue(XMLParser(data: SVGExporter().data(for: empty)).parse())
    }
}

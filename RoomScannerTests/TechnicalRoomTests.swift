import XCTest
@testable import RoomScanner

final class TechnicalRoomTests: XCTestCase {
    func testCapturedShellWithNoNotesValidatesWithoutInventingEquipment() throws {
        let shellID = UUID()
        let room = TechnicalRoom.capturedShell(id: shellID, notes: "  ")
        let data = try TechnicalRoomJSONExporter.data(for: room)
        try TechnicalJSONSchema.validate(data)
        XCTAssertEqual(room.shellID, shellID)
        XCTAssertTrue(room.notes.isEmpty)
        XCTAssertTrue(room.pipeRuns.isEmpty)
        XCTAssertTrue(room.equipment.isEmpty)
    }
    private func sample(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testSamplesValidateAndRoundTrip() throws {
        for name in ["small-boiler-room", "vertical-riser", "estimated-diameter"] {
            let data = try sample(name)
            try TechnicalJSONSchema.validate(data)
            let room = try JSONDecoder().decode(TechnicalRoom.self, from: data)
            let exported = try TechnicalRoomJSONExporter.data(for: room)
            try TechnicalJSONSchema.validate(exported)
            XCTAssertEqual(room, try JSONDecoder().decode(TechnicalRoom.self, from: exported))
            XCTAssertEqual(exported, try TechnicalRoomJSONExporter.data(for: room))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: exported) as? [String: Any])
            let runs = try XCTUnwrap(object["pipeRuns"] as? [[String: Any]])
            let length = try XCTUnwrap(runs[0]["length"] as? [String: Any])
            XCTAssertEqual(try XCTUnwrap(length["value"] as? Double), 2, accuracy: 1e-9)
            XCTAssertTrue(length["accuracyMm"] is NSNull)
        }
    }

    func testVerticalRiserAndDiameterRecomputation() throws {
        var room = try JSONDecoder().decode(TechnicalRoom.self, from: sample("vertical-riser"))
        let original = room.pipeRuns[0].centerline.value
        XCTAssertEqual(room.pipeRuns[0].elevationMin.value, 0.5)
        XCTAssertEqual(room.pipeRuns[0].elevationMax.value, 2.5)
        room.pipeRuns[0].outerDiameterMm.value = 42
        let updated = room.pipeRuns[0].centerline.value
        XCTAssertEqual(original[0].z - updated[0].z, 0.01, accuracy: 1e-9)
        XCTAssertEqual(room.pipeRuns[0].length.value, 2, accuracy: 1e-9)
        room.pipeRuns[0].insulationThicknessMm = TechnicalValue(value: 20, unit: "mm", source: .entered, method: "tape", accuracyMm: nil)
        XCTAssertEqual(updated[0].z - room.pipeRuns[0].centerline.value[0].z, 0.02, accuracy: 1e-9)
    }

    func testSupportingSurfaceStandoffAndIDs() throws {
        var room = try JSONDecoder().decode(TechnicalRoom.self, from: sample("small-boiler-room"))
        let ids = room.pipeRuns.map(\.id)
        room.pipeRuns[0].centerlineStandoff = TechnicalValue(value: 0.15, unit: "m", source: .entered, method: "tape", accuracyMm: nil)
        XCTAssertEqual(room.pipeRuns[0].centerline.value[0].z, 1.15, accuracy: 1e-9)
        let data = try TechnicalRoomJSONExporter.data(for: room)
        let decoded = try JSONDecoder().decode(TechnicalRoom.self, from: data)
        XCTAssertEqual(decoded.pipeRuns.map(\.id), ids)
        XCTAssertEqual(decoded.equipment[0].ports.count, 1)
        XCTAssertEqual(decoded.fittings[0].type.value, .valve)
    }

    func testSchemaRejectsWrongUnitsMissingProvenanceAndNegativeAccuracy() throws {
        let data = try sample("small-boiler-room")
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        for invalid in [
            text.replacingOccurrences(of: "\"units\": \"m\"", with: "\"units\": \"mm\""),
            text.replacingOccurrences(of: "\"source\": \"entered\"", with: "\"source\": \"unknown\""),
            text.replacingOccurrences(of: "\"accuracyMm\": null", with: "\"accuracyMm\": -1")
        ] {
            XCTAssertThrowsError(try TechnicalJSONSchema.validate(Data(invalid.utf8)))
        }
    }

    func testExporterRejectsInvalidNormalAndDanglingPort() throws {
        var room = try JSONDecoder().decode(TechnicalRoom.self, from: sample("small-boiler-room"))
        room.pipeRuns[0].connectedPorts = [UUID()]
        XCTAssertThrowsError(try TechnicalRoomJSONExporter.data(for: room))
        room.pipeRuns[0].connectedPorts = []
        room.pipeRuns[0].surfaceHits[0].normal.value = .init(x: 0, y: 0, z: 0)
        XCTAssertThrowsError(try TechnicalRoomJSONExporter.data(for: room))
    }
}

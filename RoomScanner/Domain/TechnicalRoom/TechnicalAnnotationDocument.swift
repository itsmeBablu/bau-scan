import Foundation

/// Sidecar annotation types; TechnicalRoom v1 interchange remains unchanged.
struct TechnicalDuctRun: Codable, Equatable, Identifiable {
    var id: UUID
    var width: TechnicalValue<Double>
    var height: TechnicalValue<Double>
    var points: [TechnicalValue<TechnicalPoint3>]
}
struct TechnicalPointMeasurement: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var start: TechnicalValue<TechnicalPoint3>
    var end: TechnicalValue<TechnicalPoint3>
    var length: Double { start.value.distance(to: end.value) }
}
struct TechnicalScaleCalibration: Codable, Equatable {
    var measurementID: UUID
    var referenceLength: TechnicalValue<Double>
    var observedLength: TechnicalValue<Double>
    var factor: Double { referenceLength.value / observedLength.value }
}
struct TechnicalPipeConnection: Codable, Equatable, Identifiable {
    enum Endpoint: String, Codable, CaseIterable { case start, end }
    var id: UUID
    var pipeID: UUID
    var endpoint: Endpoint
    var portID: UUID
}
struct TechnicalPhotoAsset: Codable, Equatable, Identifiable {
    var id: UUID
    var jpegData: Data
}
enum TechnicalAnnotationTarget: Hashable { case pipe(UUID), duct(UUID) }
struct TechnicalPointOverride: Codable, Equatable {
    var objectID: UUID
    var pointIndex: Int
    var position: TechnicalValue<TechnicalPoint3>
    var observation: TechnicalSurfaceHit?
}
struct TechnicalAnnotationDocument: Codable, Equatable {
    var room: TechnicalRoom
    var ducts: [TechnicalDuctRun] = []
    var measurements: [TechnicalPointMeasurement] = []
    var calibration: TechnicalScaleCalibration?
    var connections: [TechnicalPipeConnection] = []
    var pointOverrides: [TechnicalPointOverride] = []
    var photoAssets: [TechnicalPhotoAsset] = []
    /// Edited geometry is derived; original surface observations are never rewritten.
    var effectiveRoom: TechnicalRoom {
        var result = room
        for edit in pointOverrides {
            guard let i = result.pipeRuns.firstIndex(where: { $0.id == edit.objectID }), result.pipeRuns[i].surfaceHits.indices.contains(edit.pointIndex) else { continue }
            result.pipeRuns[i].surfaceHits[edit.pointIndex].position = edit.position
            if let observation = edit.observation { result.pipeRuns[i].surfaceHits[edit.pointIndex].normal = observation.normal }
        }
        return result
    }
    func points(for target: TechnicalAnnotationTarget) -> [TechnicalPoint3] {
        switch target {
        case .pipe(let id): return effectiveRoom.pipeRuns.first { $0.id == id }?.surfaceHits.map { $0.position.value } ?? []
        case .duct(let id):
            guard let duct = ducts.first(where: { $0.id == id }) else { return [] }
            return duct.points.enumerated().map { i, point in pointOverrides.first { $0.objectID == id && $0.pointIndex == i }?.position.value ?? point.value }
        }
    }
    func correctedLength(_ raw: Double) -> Double { raw * (calibration?.factor ?? 1) }
    var connectionWarnings: [String] {
        var warnings: [String] = []
        for pipe in room.pipeRuns {
            for end in TechnicalPipeConnection.Endpoint.allCases where !connections.contains(where: { $0.pipeID == pipe.id && $0.endpoint == end }) {
                warnings.append("Pipe \(pipe.id.uuidString.prefix(8)): unconnected \(end.rawValue)")
            }
        }
        for port in room.equipment.flatMap(\.ports) where !connections.contains(where: { $0.portID == port.id }) {
            warnings.append("Port \(port.id.uuidString.prefix(8)): unconnected")
        }
        for connection in connections {
            guard let pipe = effectiveRoom.pipeRuns.first(where: { $0.id == connection.pipeID }),
                  let port = room.equipment.flatMap(\.ports).first(where: { $0.id == connection.portID }),
                  let end = connection.endpoint == .start ? pipe.centerline.value.first : pipe.centerline.value.last else { continue }
            if end.distance(to: port.position.value) > 0.05 {
                warnings.append("Connection \(connection.id.uuidString.prefix(8)): endpoint and port differ by more than 50 mm; verify placement.")
            }
        }
        return warnings
    }
}

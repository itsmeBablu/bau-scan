import Foundation

enum TechnicalSource: String, Codable { case measured, entered, estimated, manufacturer }

/// accuracyMm stays nil until the value has a documented validation basis.
struct TechnicalValue<Value: Codable & Equatable>: Codable, Equatable {
    var value: Value
    var unit: String
    var source: TechnicalSource
    var method: String
    var accuracyMm: Double?

    enum CodingKeys: String, CodingKey { case value, unit, source, method, accuracyMm }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(unit, forKey: .unit)
        try container.encode(source, forKey: .source)
        try container.encode(method, forKey: .method)
        if let accuracyMm { try container.encode(accuracyMm, forKey: .accuracyMm) }
        else { try container.encodeNil(forKey: .accuracyMm) }
    }
}

struct TechnicalPoint3: Codable, Equatable {
    var x: Double
    var y: Double
    var z: Double
    func distance(to other: Self) -> Double {
        sqrt(pow(x - other.x, 2) + pow(y - other.y, 2) + pow(z - other.z, 2))
    }
}

/// Basis columns map shell coordinates into the room coordinate frame.
struct TechnicalTransform: Codable, Equatable {
    var translation: TechnicalPoint3
    var xAxis: TechnicalPoint3
    var yAxis: TechnicalPoint3
    var zAxis: TechnicalPoint3
}

enum TechnicalMedium: String, Codable, CaseIterable {
    case heatingSupply, heatingReturn, coldWater, hotWater, circulation
    case waste, gas, condensate, refrigerant, ventilation, other
}

struct TechnicalSurfaceHit: Codable, Equatable {
    var position: TechnicalValue<TechnicalPoint3>
    /// Normal points from the observed visible surface toward the camera.
    var normal: TechnicalValue<TechnicalPoint3>
}

struct TechnicalPipeRun: Codable, Equatable {
    var id: UUID
    var medium: TechnicalValue<TechnicalMedium>
    var systemLabel: TechnicalValue<String>
    var material: TechnicalValue<String>
    var nominalDN: TechnicalValue<String>?
    var outerDiameterMm: TechnicalValue<Double>
    var wallThicknessMm: TechnicalValue<Double>?
    var insulationThicknessMm: TechnicalValue<Double>?
    var surfaceHits: [TechnicalSurfaceHit]
    /// Entered standoff from supporting surface to the pipe centre, in metres.
    /// When absent, hits are on the visible outer pipe/insulation surface.
    var centerlineStandoff: TechnicalValue<Double>?
    var connectedPorts: [UUID]

    var centerline: TechnicalValue<[TechnicalPoint3]> {
        let offset = centerlineStandoff?.value ?? -(outerDiameterMm.value / 2 + (insulationThicknessMm?.value ?? 0)) / 1000
        let points = surfaceHits.map { hit in
            let p = hit.position.value, n = hit.normal.value
            let length = sqrt(n.x * n.x + n.y * n.y + n.z * n.z)
            return TechnicalPoint3(x: p.x + n.x / length * offset,
                                   y: p.y + n.y / length * offset,
                                   z: p.z + n.z / length * offset)
        }
        return TechnicalValue(value: points, unit: "m", source: .estimated,
                              method: centerlineStandoff == nil ? "surfaceHitsMinusOuterRadius" : "supportSurfacePlusEnteredStandoff",
                              accuracyMm: nil)
    }

    var length: TechnicalValue<Double> {
        let points = centerline.value
        let length = zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        return TechnicalValue(value: length, unit: "m", source: .estimated, method: "sumOfCenterlineSegments", accuracyMm: nil)
    }

    var elevationMin: TechnicalValue<Double> {
        TechnicalValue(value: centerline.value.map(\.y).min() ?? 0, unit: "m", source: .estimated, method: "centerlineMinimumY", accuracyMm: nil)
    }
    var elevationMax: TechnicalValue<Double> {
        TechnicalValue(value: centerline.value.map(\.y).max() ?? 0, unit: "m", source: .estimated, method: "centerlineMaximumY", accuracyMm: nil)
    }
}

enum TechnicalEquipmentType: String, Codable, CaseIterable {
    case boiler, heatPump, bufferTank, dhwTank, manifold, pump, expansionVessel
    case meter, valveGroup, electricalPanel, other
}

struct TechnicalPort: Codable, Equatable {
    var id: UUID
    /// Room-space position and outward room-space unit direction.
    var position: TechnicalValue<TechnicalPoint3>
    var direction: TechnicalValue<TechnicalPoint3>
    var nominalDN: TechnicalValue<String>?
    var medium: TechnicalValue<TechnicalMedium>
}

struct TechnicalEquipment: Codable, Equatable {
    var id: UUID
    var type: TechnicalValue<TechnicalEquipmentType>
    var name: TechnicalValue<String>
    var manufacturer: TechnicalValue<String>?
    var model: TechnicalValue<String>?
    var center: TechnicalValue<TechnicalPoint3>
    /// Local width (X), height (Y), depth (Z), all metres.
    var size: TechnicalValue<TechnicalPoint3>
    /// Right-handed rotation about +Y, radians.
    var rotation: TechnicalValue<Double>
    var ports: [TechnicalPort]
    var photoRefs: [UUID]
}

enum TechnicalFittingType: String, Codable { case valve, elbow, tee, reducer, flange, cross, cap, other }
struct TechnicalFitting: Codable, Equatable {
    var id: UUID
    var type: TechnicalValue<TechnicalFittingType>
    var position: TechnicalValue<TechnicalPoint3>
    var nominalDN: TechnicalValue<String>?
    var hostPipeRunId: UUID
}

struct TechnicalPhoto: Codable, Equatable {
    var id: UUID
    var reference: TechnicalValue<String>
}

struct TechnicalRoom: Codable, Equatable {
    var id: UUID
    /// Reference only, never a change to the shell package.
    var shellID: UUID
    var shellToRoom: TechnicalValue<TechnicalTransform>
    var northAzimuthDeg: TechnicalValue<Double>?
    var pipeRuns: [TechnicalPipeRun]
    var equipment: [TechnicalEquipment]
    var fittings: [TechnicalFitting]
    var notes: [TechnicalValue<String>]
    var photos: [TechnicalPhoto]

    /// Starts an annotation document for one captured shell. Equipment is never inferred from shell geometry.
    static func capturedShell(id: UUID, notes: String) -> TechnicalRoom {
        let frame = TechnicalTransform(translation: .init(x: 0, y: 0, z: 0), xAxis: .init(x: 1, y: 0, z: 0),
                                       yAxis: .init(x: 0, y: 1, z: 0), zAxis: .init(x: 0, y: 0, z: 1))
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return TechnicalRoom(id: UUID(), shellID: id,
            shellToRoom: TechnicalValue(value: frame, unit: "m", source: .estimated, method: "roomPlanLocalFrame", accuracyMm: nil),
            pipeRuns: [], equipment: [], fittings: [],
            notes: trimmed.isEmpty ? [] : [TechnicalValue(value: trimmed, unit: "text", source: .entered, method: "surveyNotes", accuracyMm: nil)],
            photos: [])
    }
}

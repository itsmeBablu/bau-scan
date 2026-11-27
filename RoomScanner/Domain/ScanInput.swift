import Foundation
import simd

/// Platform-neutral snapshot of a RoomPlan scan boundary:
/// `Scan/` (iOS) converts `CapturedRoom` to `ScanInput`; Domain logic, tests,
/// (iOS and macOS targets) and unit test fixtures only depend on this type.
/// Units: meters. RoomPlan coordinates: Y up, floor = XZ plane.
struct ScanInput: Codable, Equatable {
    var id: UUID
    var story: Int
    var sectionLabels: [RoomLabel]
    var surfaces: [ScanSurface]
    var objects: [ScanObject]
    /// Optional for older packages; preserves RoomPlan's spatial room labels.
    var sections: [ScanSection]? = nil

    init(id: UUID = UUID(), story: Int = 0, sectionLabels: [RoomLabel] = [], surfaces: [ScanSurface], objects: [ScanObject] = []) {
        self.id = id; self.story = story; self.sectionLabels = sectionLabels; self.surfaces = surfaces; self.objects = objects
    }

    var walls: [ScanSurface] { surfaces.filter { $0.category == .wall } }
    var floors: [ScanSurface] { surfaces.filter { $0.category == .floor } }
    var openings: [ScanSurface] { surfaces.filter { $0.category.isOpening } }
}

struct ScanSection: Codable, Equatable {
    var label: RoomLabel
    var center: SIMD3<Float>
}

struct ScanSurface: Codable, Equatable {
    enum Category: String, Codable { case wall, door, window, opening, floor
        var isOpening: Bool { self == .door || self == .window || self == .opening }
    }
    var id: UUID
    var category: Category
    /// (width, height, depth) in meters — `CapturedRoom.Surface.dimensions`.
    var dimensions: SIMD3<Float>
    var transform: simd_float4x4
    var confidence: Confidence
    /// Supporting wall of a door / window / opening.
    var parentID: UUID?
    /// Polygon vertices (non-rectangular walls, floors) — empty if rectangular.
    var polygonCorners: [SIMD3<Float>]

    init(id: UUID = UUID(), category: Category, dimensions: SIMD3<Float>, transform: simd_float4x4, confidence: Confidence = .high, parentID: UUID? = nil, polygonCorners: [SIMD3<Float>] = []) {
        self.id = id; self.category = category; self.dimensions = dimensions; self.transform = transform
        self.confidence = confidence; self.parentID = parentID; self.polygonCorners = polygonCorners
    }
}

struct ScanObject: Codable, Equatable {
    var id: UUID
    /// `CapturedRoom.Object.Category` en texte (`table`, `sofa`, `bed`, …).
    var category: String
    var dimensions: SIMD3<Float>
    var transform: simd_float4x4
    var confidence: Confidence

    init(id: UUID = UUID(), category: String, dimensions: SIMD3<Float>, transform: simd_float4x4, confidence: Confidence = .high) {
        self.id = id; self.category = category; self.dimensions = dimensions; self.transform = transform; self.confidence = confidence
    }
}

// MARK: - Codable support for simd_float4x4 (stored column by column)

extension simd_float4x4: Codable {
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        let v = try (0..<16).map { _ in try c.decode(Float.self) }
        self.init(columns: (SIMD4(v[0], v[1], v[2], v[3]), SIMD4(v[4], v[5], v[6], v[7]),
                            SIMD4(v[8], v[9], v[10], v[11]), SIMD4(v[12], v[13], v[14], v[15])))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        for col in [columns.0, columns.1, columns.2, columns.3] { for i in 0..<4 { try c.encode(col[i]) } }
    }
}

extension simd_float4x4 {
    /// Transform matrix for RoomPlan surface: `yaw` rotation around Y (radians),
    /// puis translation. Sert aux fixtures et aux tests.
    static func roomPlacement(x: Float, y: Float, z: Float, yaw: Float = 0) -> simd_float4x4 {
        let c = cos(yaw), s = sin(yaw)
        return simd_float4x4(columns: (
            SIMD4(c, 0, -s, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(s, 0, c, 0),
            SIMD4(x, y, z, 1)))
    }
}

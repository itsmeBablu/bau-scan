import Foundation

/// House-specific observations. No Technical Room or RoomPlan dependency.
struct RadiatorPoint: Codable, Equatable {
    var x: Double; var y: Double; var z: Double
    static let zero = Self(x: 0,y: 0,z: 0)
    static func + (a: Self,b: Self) -> Self { .init(x: a.x+b.x,y: a.y+b.y,z: a.z+b.z) }
    static func - (a: Self,b: Self) -> Self { .init(x: a.x-b.x,y: a.y-b.y,z: a.z-b.z) }
    static func * (a: Self,s: Double) -> Self { .init(x: a.x*s,y: a.y*s,z: a.z*s) }
    func dot(_ b: Self) -> Double { x*b.x+y*b.y+z*b.z }
    func cross(_ b: Self) -> Self { .init(x: y*b.z-z*b.y,y: z*b.x-x*b.z,z: x*b.y-y*b.x) }
    var length: Double { sqrt(dot(self)) }
    var unit: Self { length > 1e-9 ? self*(1/length) : .zero }
    var valid: Bool { [x,y,z].allSatisfy { $0.isFinite && abs($0) < 1000 } }
}

struct RadiatorDimension: Codable, Equatable {
    enum Source: String,Codable,CaseIterable { case scanEstimate, mountingAssumption, tapeMeasure, laserMeasure, manufacturer }
    var metres: Double
    var source: Source
    var method: String
    var reference: String? = nil
    /// No automatic claim of millimetre accuracy.
    var accuracyMm: Double? = nil
    var label: String {
        switch source {
        case .scanEstimate: "Scan estimate"
        case .mountingAssumption: "Assumed mounting value"
        case .tapeMeasure: "Entered tape measurement"
        case .laserMeasure: "Entered laser measurement"
        case .manufacturer: "Manufacturer value"
        }
    }
    func validate(allowZero: Bool = false) throws {
        guard metres.isFinite,metres >= (allowZero ? 0 : 0.001),metres <= 10,
              !method.isEmpty,method.count <= 200,(reference?.count ?? 0) <= 1000,
              accuracyMm == nil else { throw HouseRadiatorSurvey.Failure.invalid }
        if source == .manufacturer || source == .mountingAssumption {
            guard reference?.isEmpty == false else { throw HouseRadiatorSurvey.Failure.invalid }
        }
    }
}

enum RadiatorMountingPreset: String,Codable,CaseIterable {
    case none, kermiLongConsole30, kermiLongConsole50
    var title: String {
        switch self {
        case .none: "No assumption"
        case .kermiLongConsole30: "KERMI long wall console: 30 mm (assumed)"
        case .kermiLongConsole50: "KERMI long wall console: 50 mm (assumed)"
        }
    }
    var gap: RadiatorDimension? {
        guard self != .none else { return nil }
        return .init(metres: self == .kermiLongConsole30 ? 0.03 : 0.05,source: .mountingAssumption,
            method: "userSelectedModelSpecificMountingExample",reference: "KERMI long wall console; https://www.youtube.com/watch?v=zxw3laHBoAs")
    }
}

struct RadiatorSurfaceSample: Codable,Equatable {
    var point: RadiatorPoint
    var normal: RadiatorPoint
    var viewpoint: Int
}

struct HouseRadiator: Codable,Equatable,Identifiable {
    var id = UUID()
    var roomID: UUID
    var wallID: UUID?
    var name: String
    var width: RadiatorDimension
    var height: RadiatorDimension
    var depth: RadiatorDimension?
    /// Finished wall to the rear face of the radiator body, excluding pipes/valves.
    var wallGap: RadiatorDimension?
    var wallToFront: RadiatorDimension
    var frontCorners: [RadiatorPoint]
    var wallSample: RadiatorSurfaceSample
    var samples: [RadiatorSurfaceSample]
    var viewpointCount: Int
    var photoJPEG: Data?
    enum Identification: String,Codable { case automaticCandidate, userConfirmed }
    /// Nil in legacy surveys; geometry proposals must not imply semantic verification.
    var identification: Identification? = nil
    var createdAt = Date()
    var notes = ""
    /// Only true when captured using the same uninterrupted House AR session.
    var capturedInHouseCoordinates: Bool? = nil
    var houseFloorElevation: Double? = nil
    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,name.count <= 120,notes.count <= 2000,
              frontCorners.count == 3,frontCorners.allSatisfy(\.valid),wallSample.point.valid,
              wallSample.normal.valid,abs(wallSample.normal.length-1) < 0.01,
              samples.count <= 8000,samples.allSatisfy({ $0.point.valid && $0.normal.valid && abs($0.normal.length-1) < 0.01 && $0.viewpoint >= 0 }),
              viewpointCount >= 0,viewpointCount <= 100_000,(photoJPEG?.count ?? 0) <= 2 * 1_048_576,
              createdAt.timeIntervalSince1970.isFinite else { throw HouseRadiatorSurvey.Failure.invalid }
        if let houseFloorElevation {
            guard houseFloorElevation.isFinite,abs(houseFloorElevation) < 1000 else { throw HouseRadiatorSurvey.Failure.invalid }
        }
        try width.validate(); try height.validate(); try wallToFront.validate()
        try depth?.validate(); try wallGap?.validate(allowZero: true)
        if let gap = wallGap,let depth, gap.source == .scanEstimate,depth.source == .scanEstimate {
            guard abs(gap.metres+depth.metres-wallToFront.metres) < 0.02 else { throw HouseRadiatorSurvey.Failure.invalid }
        }
    }
}

struct HouseRadiatorSurvey: Codable,Equatable {
    var schemaVersion = 1
    var houseID: UUID
    var radiators: [HouseRadiator] = []
    enum Failure: LocalizedError {
        case invalid, incomplete, wrongWall, unassigned
        var errorDescription: String? {
            switch self {
            case .invalid: "The radiator survey contains invalid dimensions or capture evidence."
            case .incomplete: "Confirm a detected radiator body and capture its visible surfaces from at least two viewpoints. Keep the full body and adjacent wall visible while detecting."
            case .wrongWall: "Choose the finished wall beside the radiator, parallel to its front."
            case .unassigned: "A captured radiator could not be matched to a scanned House wall. The House and radiator observations have not been saved yet."
            }
        }
    }
    func validate(for house: House) throws {
        guard schemaVersion == 1,houseID == house.id,radiators.count <= 100,
              Set(radiators.map(\.id)).count == radiators.count,
              radiators.reduce(0,{ $0+$1.samples.count }) <= 150_000,
              radiators.reduce(0,{ $0+($1.photoJPEG?.count ?? 0) }) <= 24 * 1_048_576 else { throw Failure.invalid }
        for item in radiators {
            guard let room = house.allRooms.first(where: { $0.id == item.roomID }),
                  item.wallID == nil || room.walls.contains(where: { $0.id == item.wallID }) else { throw Failure.invalid }
            try item.validate()
        }
    }
}

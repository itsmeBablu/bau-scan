import Foundation

/// Export subject: a room (`.roomscan`) or house (`.housescan`). Downstream
/// (`ExportService`, export sheet, drag-and-drop, README) operates on this type.
struct ExportSubject: Equatable {
    enum Kind: Equatable { case room, house }
    var kind: Kind
    var id: UUID
    var name: String
    var createdAt: Date
    var house: House
    /// Parametric USDZ model from package, if present.
    var usdzURL: URL?
    /// Raw scan mesh (iPhone rooms only).
    var usdzMeshURL: URL?
    var sourcePackageURL: URL? = nil

    init(record: RoomRecord, house: House, packageURL: URL?) {
        kind = .room; id = record.id; name = record.name; createdAt = record.createdAt; self.house = house
        sourcePackageURL = packageURL
        usdzURL = packageURL.flatMap { RoomPackage.usdzURL(in: $0) }
        usdzMeshURL = packageURL.flatMap { RoomPackage.usdzMeshURL(in: $0) }
    }

    init(record: RoomRecord, plan: FloorPlan, packageURL: URL?) {
        self.init(record: record, house: House(room: plan), packageURL: packageURL)
    }

    init(record: HouseRecord, house: House, packageURL: URL?) {
        kind = .house; id = record.id; name = record.name; createdAt = record.createdAt; self.house = house
        sourcePackageURL = packageURL
        usdzURL = packageURL.flatMap { HousePackage.usdzURL(in: $0) }
        usdzMeshURL = nil
    }
}

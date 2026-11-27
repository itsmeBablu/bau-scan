import Foundation

/// Rebuild an editable seed only from its original saved source. Never write it.
enum StudioScanSeed {
    static func load(source:SceneEditDocument.Source,id:UUID,root:URL) throws -> SceneEditDocument {
        let location = StorageLocation(kind:.local,documentsURL:root)
        switch source {
        case .house:
            let url = location.housePackageURL(for:id)
            var seed = SceneEditDocument.seed(house:try HousePackage.readHouse(from:url),source:source,id:id,
                                              scans:try HousePackage.readStructure(from:url)?.rooms ?? [])
            seed.includeRadiators(try HousePackage.readRadiators(from:url)?.radiators ?? [])
            return seed
        case .room:
            let url = location.packageURL(for:id)
            return .seed(house:House(room:try RoomPackage.readPlan(from:url)),source:source,id:id,
                         scans:try RoomPackage.readScan(from:url).map { [$0] } ?? [])
        case .technical:
            let url = root.appendingPathComponent("TechnicalRooms").appendingPathComponent(id.uuidString).appendingPathExtension("technicalroom")
            return try SceneEditDocument.technical(TechnicalRoomPackage.read(from:url))
        }
    }
}

import Foundation

enum HouseImportCopy {
    /// One map for house, room and photo identities across neutral JSON and asset paths.
    /// Opaque Apple captures and binary assets remain byte-for-byte original evidence.
    static func write(from source: URL,to destination: URL,name: String) throws -> HouseRecord {
        let fm = FileManager.default,house = try HousePackage.readHouse(from:source)
        var ids = Set(house.allRooms.map(\.id)); ids.insert(house.id)
        let nested = HousePackage.roomPackageURLs(in:source)
        for url in [source]+nested {
            if url != source { ids.insert(try RoomPackage.readRecord(from:url).id) }
            for photo in try SurveyPhotoStore.readCoordinated(from:url).photos ?? [] { ids.insert(photo.id) }
        }
        let structure = try HousePackage.readStructure(from:source)
        for room in structure?.rooms ?? [] { ids.insert(room.id) }
        var mapping: [UUID:UUID] = [:]
        for id in ids { mapping[id] = id == house.id ? UUID(uuidString:destination.deletingPathExtension().lastPathComponent) : UUID() }
        guard let newID = mapping[house.id] else { throw CocoaError(.fileWriteInvalidFileName) }
        if let structure { mapping[structure.id] = newID }
        let stage = try PackageReplacement.staging(for:destination)
        defer { try? fm.removeItem(at:stage) }
        try RoomPackage.coordinatedRead(at:source) { try fm.copyItem(at:$0,to:stage) }
        guard let enumerator = fm.enumerator(at:stage,includingPropertiesForKeys:[.isSymbolicLinkKey]) else { throw CocoaError(.fileReadUnknown) }
        let urls = enumerator.allObjects.compactMap { $0 as? URL }
        func remap(_ value: Any) -> Any {
            if let text = value as? String {
                if let id = UUID(uuidString:text),let replacement = mapping[id] { return replacement.uuidString }
                let path = URL(fileURLWithPath:text),stem = path.deletingPathExtension().lastPathComponent
                if let id = UUID(uuidString:stem),let replacement = mapping[id] { return text.replacingOccurrences(of:stem,with:replacement.uuidString) }
                return text
            }
            if let array = value as? [Any] { return array.map(remap) }
            if let object = value as? [String:Any] { return object.mapValues(remap) }
            return value
        }
        for file in urls {
            guard try file.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink != true else { throw CocoaError(.fileReadNoPermission) }
            guard file.pathExtension == "json",!["room.json","structure-apple.json"].contains(file.lastPathComponent) else { continue }
            let object = try JSONSerialization.jsonObject(with:Data(contentsOf:file))
            try JSONSerialization.data(withJSONObject:remap(object),options:[.sortedKeys]).write(to:file,options:.atomic)
        }
        for file in urls.sorted(by:{ $0.path.count > $1.path.count }) {
            let stem = file.deletingPathExtension().lastPathComponent
            if let id = UUID(uuidString:stem),let replacement = mapping[id] {
                let renamed = file.deletingLastPathComponent().appendingPathComponent(replacement.uuidString).appendingPathExtension(file.pathExtension)
                try fm.moveItem(at:file,to:renamed)
            }
        }
        var record = try HousePackage.readRecord(from:stage),copy = try HousePackage.readHouse(from:stage)
        record.id = newID; record.name = name; copy.id = newID; copy.name = name
        try HousePackage.update(record:record,house:copy,in:stage)
        try RoomPackage.coordinatedWrite(at:destination,options:.forReplacing) { try PackageReplacement.commit(stage,to:$0) }
        return record
    }
}

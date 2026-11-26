import Foundation

/// Only metadata and source URLs are retained while building the export table.
struct SurveyPhotoExportSource {
    let photo: SurveyPhoto
    let root: URL
    let roomName: String
    let byteCount: Int
    static func list(from root: URL,house: House) throws -> [Self] {
        try list(from:root,roomNames:Dictionary(grouping:house.allRooms,by:\.id).mapValues { $0.first?.name ?? "" })
    }
    static func list(from root: URL,roomNames:[UUID:String]) throws -> [Self] {
        try RoomPackage.coordinatedRead(at:root) { root in
            try SafePackageRead.validate(root)
            let meta = root.appendingPathComponent("survey-photos.json")
            guard FileManager.default.fileExists(atPath:meta.path) else { return [] }
            let photos = try RoomPackage.decoder.decode([SurveyPhoto].self,from:SafePackageRead.data(meta,root:root,maximum:1_048_576,preflight:false))
            guard photos.count <= 200,Set(photos.map(\.id)).count == photos.count else { throw CocoaError(.fileReadCorruptFile) }
            var total = 0
            return try photos.map { photo in
                try Task.checkCancellation(); try photo.validate()
                let info = try root.appendingPathComponent(photo.jpegPath).resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
                guard info.isRegularFile == true,info.isSymbolicLink != true,let bytes = info.fileSize,bytes >= 2,bytes <= 4*1_048_576 else { throw CocoaError(.fileReadCorruptFile) }
                total += bytes; guard total <= SurveyPhotoStore.maximumBytes else { throw CocoaError(.fileReadTooLarge) }
                return Self(photo:photo,root:root,roomName:photo.roomID.flatMap { roomNames[$0] } ?? AppLanguage.text("Unassigned room"),byteCount:bytes)
            }
        }
    }
    func copy(to target: URL) throws -> Int64 {
        try Task.checkCancellation()
        return try RoomPackage.coordinatedRead(at:root) { source in
            // Bound a single asset read, release it before copying the next image.
            let data = try SafePackageRead.data(source.appendingPathComponent(photo.jpegPath),root:source,maximum:4*1_048_576,preflight:false)
            guard data.starts(with:[0xff,0xd8]) else { throw CocoaError(.fileReadCorruptFile) }
            try Task.checkCancellation(); try data.write(to:target,options:.atomic)
            return Int64(data.count)
        }
    }
}

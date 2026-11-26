import Foundation

/// A lazy source reference, never an image-byte collection or a persisted format.
struct ProjectPhotoAsset: Identifiable {
    let reference: ProjectReference
    let photo: SurveyPhoto
    let roomName: String
    let root: URL
    let relativePath: String
    var id: String { reference.id+":"+photo.id.uuidString }
    var url: URL { root.appendingPathComponent(relativePath) }
    var title: String { roomName+" · "+String(photo.number) }
    func image() throws -> SurveyPhotoImage {
        try RoomPackage.coordinatedRead(at:root) { source in
            try Task.checkCancellation()
            let bytes = try SafePackageRead.data(source.appendingPathComponent(relativePath),root:source,maximum:4*1_048_576)
            guard bytes.starts(with:[0xff,0xd8]) else { throw CocoaError(.fileReadCorruptFile) }
            return SurveyPhotoImage(photo:photo,jpegData:bytes,roomName:roomName)
        }
    }
    static func list(entry:ProjectLibraryEntry,summary:ProjectScanSummary?) throws -> [Self] {
        if entry.reference.kind != .technicalRoom {
            let names = Dictionary(grouping:summary?.roomDetails ?? [],by:\.id).mapValues { $0.first?.name ?? "" }
            return try SurveyPhotoExportSource.list(from:entry.url,roomNames:names).map {
                Self(reference:entry.reference,photo:$0.photo,roomName:$0.roomName,root:$0.root,relativePath:$0.photo.jpegPath)
            }
        }
        return try RoomPackage.coordinatedRead(at:entry.url) { root in
            let file = root.appendingPathComponent("evidence.json")
            guard FileManager.default.fileExists(atPath:file.path) else { return [] }
            let evidence = try JSONDecoder().decode(EvidenceIndex.self,from:SafePackageRead.data(file,root:root,maximum:96*1_048_576))
            guard evidence.keyframes.count <= 32,Set(evidence.keyframes.map(\.id)).count == evidence.keyframes.count else { throw CocoaError(.fileReadCorruptFile) }
            return try evidence.keyframes.filter { $0.userPhoto == true }.enumerated().map { index,frame in
                let photo = SurveyPhoto(id:frame.id,roomID:entry.reference.itemID,number:index+1,pose:frame.depth.cameraTransform,timestamp:frame.depth.timestamp,capturedAt:frame.capturedAt)
                try photo.validate()
                let path = "capture-images/"+frame.id.uuidString+".jpg"
                let info = try root.appendingPathComponent(path).resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
                guard info.isRegularFile == true,info.isSymbolicLink != true,let bytes = info.fileSize,(2...4*1_048_576).contains(bytes) else { throw CocoaError(.fileReadCorruptFile) }
                return Self(reference:entry.reference,photo:photo,roomName:entry.title,root:root,relativePath:path)
            }
        }
    }
    /// Decode only photo metadata; depth grids, mesh, world maps and image bytes are skipped.
    private struct EvidenceIndex: Decodable {
        struct Frame: Decodable {
            struct Depth: Decodable { let cameraTransform:[Double]; let timestamp:Double }
            let id:UUID
            let userPhoto:Bool?
            let capturedAt:Date?
            let depth:Depth
        }
        let keyframes:[Frame]
    }
}

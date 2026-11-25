import Foundation

enum SurveyPhotoStore {
    static let maximumBytes = 64 * 1_048_576
    static func write(_ photos: [SurveyPhoto]?, assets: [UUID:Data], to root: URL) throws {
        guard let photos,!photos.isEmpty else { return }
        guard photos.count <= 200,Set(photos.map(\.id)).count == photos.count,
              assets.values.reduce(0,{ $0+$1.count }) <= maximumBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        try FileManager.default.createDirectory(at:root.appendingPathComponent("survey-photos"),withIntermediateDirectories:true)
        for photo in photos {
            try photo.validate()
            guard let bytes = assets[photo.id],bytes.count <= 4*1_048_576,bytes.starts(with:[0xff,0xd8]) else { throw CocoaError(.fileWriteInvalidFileName) }
            try bytes.write(to:root.appendingPathComponent(photo.jpegPath))
        }
        try RoomPackage.encoder.encode(photos).write(to:root.appendingPathComponent("survey-photos.json"))
    }
    static func read(from root: URL) throws -> (photos:[SurveyPhoto]?,assets:[UUID:Data]) {
        let meta = root.appendingPathComponent("survey-photos.json")
        guard FileManager.default.fileExists(atPath:meta.path) else { return (nil,[:]) }
        try SafePackageRead.validate(root)
        func data(_ url: URL,limit: Int) throws -> Data {
            try SafePackageRead.data(url,root:root,maximum:limit,preflight:false)
        }
        let photos = try RoomPackage.decoder.decode([SurveyPhoto].self,from:data(meta,limit:1_048_576))
        guard photos.count <= 200,Set(photos.map(\.id)).count == photos.count else { throw CocoaError(.fileReadCorruptFile) }
        var assets: [UUID:Data] = [:], total = 0
        for photo in photos {
            try photo.validate()
            let bytes = try data(root.appendingPathComponent(photo.jpegPath),limit:4*1_048_576)
            total += bytes.count
            guard total <= maximumBytes,bytes.starts(with:[0xff,0xd8]) else { throw CocoaError(.fileReadCorruptFile) }
            assets[photo.id] = bytes
        }
        return (photos,assets)
    }
    static func readCoordinated(from root: URL) throws -> (photos:[SurveyPhoto]?,assets:[UUID:Data]) {
        try RoomPackage.coordinatedRead(at:root) { try read(from:$0) }
    }
    static func images(from root: URL,house: House) throws -> [SurveyPhotoImage] {
        let data = try readCoordinated(from:root)
        return (data.photos ?? []).compactMap { photo in
            guard let bytes = data.assets[photo.id] else { return nil }
            return .init(photo:photo,jpegData:bytes,roomName:house.allRooms.first { $0.id == photo.roomID }?.name ?? AppLanguage.text("Unassigned room"))
        }
    }
    static func images(technical package: TechnicalRoomPackage,studio: Bool = false) -> [SurveyPhotoImage] {
        let floor: Double
        if studio,let snapshot = TechnicalSavedMeshGeometry.latest(in:package.journal.meshes),
           let geometry = try? TechnicalSavedMeshGeometry(snapshot:snapshot,reference:package.alignment.referenceFrame) {
            floor = geometry.center.y-geometry.extent.y/2
        } else { floor = 0 }
        return package.evidence.keyframes.filter { $0.userPhoto == true }.enumerated().map { index,frame in
            let pose = frame.depth.cameraTransform
            var display = package.alignment.referenceFrame.map { SurveyPhoto.transformedPose(pose,by:$0) } ?? pose
            if display.count == 16 { display[13] -= floor }
            return .init(photo:.init(id:frame.id,roomID:package.manifest.id,number:index+1,pose:pose,displayPose:display,timestamp:frame.depth.timestamp),
                         jpegData:frame.jpegData,roomName:package.manifest.name)
        }
    }
}

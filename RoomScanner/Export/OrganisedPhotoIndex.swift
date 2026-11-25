import Foundation

enum OrganisedPhotoIndex {
    struct Entry {
        let photo: SurveyPhoto
        let room: String
        let story: Int?
        let number: Int
        let path: String
    }
    static func records(_ entries: [Entry],sourceID: UUID,root: URL) throws -> [[String:Any]] {
        try SafePackageRead.validate(root)
        return try entries.map { entry in
            try Task.checkCancellation()
            try entry.photo.validate()
            let components = entry.path.split(separator:"/",omittingEmptySubsequences:false)
            guard !components.isEmpty,components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.contains(":") }) else { throw CocoaError(.fileReadNoPermission) }
            let file = root.appendingPathComponent(entry.path),bytes = try file.resourceValues(forKeys:[.fileSizeKey]).fileSize
            guard let bytes,bytes > 0 else { throw CocoaError(.fileReadCorruptFile) }
            let m = entry.photo.viewingPose
            return ["photoID":entry.photo.id.uuidString,"sourceID":sourceID.uuidString,
                "roomID":entry.photo.roomID.map { $0.uuidString as Any } ?? NSNull(),"roomName":entry.room,
                "floorIndex":entry.story.map { $0 as Any } ?? NSNull(),"number":entry.number,"originalNumber":entry.photo.number,
                "originalFilename":entry.photo.id.uuidString+".jpg","exportedFilename":file.lastPathComponent,"path":entry.path,
                "captureTimestamp":entry.photo.timestamp,"capturedAt":entry.photo.capturedAt.map { ISO8601DateFormatter().string(from:$0) as Any } ?? NSNull(),
                "rawCameraPose":entry.photo.pose,"displayCameraPose":entry.photo.displayPose.map { $0 as Any } ?? NSNull(),
                "level":entry.story.map { "level-\($0)" } ?? "unassigned","room":entry.room,"file":entry.path,
                "timestamp":entry.photo.capturedAt.map { ISO8601DateFormatter().string(from:$0) } ?? String(entry.photo.timestamp),
                "pos_x":m[12],"pos_y":m[13],"pos_z":m[14],"yaw":atan2(m[8],m[10]),"pitch":asin(min(1,max(-1,-m[9]))),"roll":atan2(m[1],m[5]),
                "coordinateSystem":"rawCameraPose: original capture frame; displayCameraPose: viewer room frame when present; Y-up metres; not GPS",
                "positionFrame":"displayCameraPose when present, otherwise rawCameraPose","bytes":bytes,"sha256":try ExportChecksum.sha256(file),
                "deviceValidationPending":true,"accuracyMm":NSNull()]
        }
    }
    static func csv(_ records: [[String:Any]]) -> Data {
        func cell(_ raw: Any) -> String {
            if raw is NSNull { return "\"\"" }
            let value = String(describing:raw)
            let prefix = String(value.trimmingCharacters(in:.whitespacesAndNewlines).prefix(1))
            let safe = !(raw is NSNumber) && ["=","+","-","@"].contains(prefix) ? "'"+value : value
            return "\""+safe.replacingOccurrences(of:"\"",with:"\"\"")+"\""
        }
        // Keep the established leading columns; append stable identity/integrity data.
        let keys = ["number","level","room","file","timestamp","pos_x","pos_y","pos_z","yaw","pitch","roll","photoID","sourceID","roomID","floorIndex","originalNumber","originalFilename","exportedFilename","bytes","sha256","coordinateSystem"]
        let rows: [[Any]] = [keys.map { $0 as Any }]+records.map { record in keys.map { record[$0] ?? NSNull() } }
        return Data((rows.map { $0.map(cell).joined(separator:",") }.joined(separator:"\r\n")+"\r\n").utf8)
    }
}

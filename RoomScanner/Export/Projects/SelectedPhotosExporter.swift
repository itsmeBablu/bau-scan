import Foundation

/// Explicit selection handoff. Reads one JPEG at a time; never rewrites source packages.
enum SelectedPhotosExporter {
    static func export(project:RenovationProject,assets:[ProjectPhotoAsset],organization:[String:ScanOrganization],summaries:[String:ProjectScanSummary],locale:Locale,to destination:URL) throws {
        guard destination.pathExtension.lowercased() == "zip" else { throw CocoaError(.fileWriteInvalidFileName) }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("selected-photos-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:staging) }
        let root = staging.appendingPathComponent(ArchivePath.component(project.name,fallback:"Project"))
        try files(project:project,assets:assets,organization:organization,summaries:summaries,locale:locale,in:root)
        try ArchiveExporter.zip(directory:root,to:destination)
    }

    static func files(project:RenovationProject,assets:[ProjectPhotoAsset],organization:[String:ScanOrganization],summaries:[String:ProjectScanSummary],locale:Locale,in root:URL) throws {
        let allowed = Set(project.references)
        guard !assets.isEmpty,assets.count <= 1000,Set(assets.map(\.id)).count == assets.count,
              assets.allSatisfy({ allowed.contains($0.reference) && !$0.reference.kind.rawValue.hasPrefix("design") }) else { throw CocoaError(.fileWriteNoPermission) }
        if FileManager.default.fileExists(atPath:root.path) {
            let info = try root.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
            guard info.isDirectory == true,info.isSymbolicLink != true,
                  try FileManager.default.contentsOfDirectory(atPath:root.path).isEmpty else { throw CocoaError(.fileWriteFileExists) }
        }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        var layout = PhotoArchiveLayout()
        var records:[SurveyPhotoArchiveWriter.Entry] = [],items:[[String:Any]] = [],totalBytes = 0
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        func write(_ data:Data,_ path:String) throws {
            try Task.checkCancellation()
            guard data.count <= 512*1_048_576-totalBytes else { throw CocoaError(.fileWriteOutOfSpace) }
            let target = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
            try data.write(to:target,options:.atomic); totalBytes += data.count
            items.append(["path":path,"bytes":data.count,"sha256":try ExportChecksum.sha256(target)])
        }
        for asset in assets.sorted(by:{ $0.id < $1.id }) {
            try Task.checkCancellation(); try asset.photo.validate()
            let value = organization[asset.reference.id]
            guard value == nil || value?.kind == asset.reference.kind else { throw CocoaError(.fileReadCorruptFile) }
            let paths = try layout.paths(photo:asset.photo,roomName:asset.roomName,sourceID:asset.reference.id,organization:value,summary:summaries[asset.reference.id],locale:locale)
            let jpegPath = paths.image,cameraPath = paths.camera
            try write(asset.image().jpegData,jpegPath)
            let camera = SurveyPhotoArchiveWriter.Camera(photoID:asset.photo.id,roomID:asset.photo.roomID,number:asset.photo.number,imageFile:URL(fileURLWithPath:jpegPath).lastPathComponent,rawCameraPose:asset.photo.pose,displayCameraPose:asset.photo.displayPose,captureTimestamp:asset.photo.timestamp,capturedAt:asset.photo.capturedAt,sourceID:asset.reference.id)
            try write(encoder.encode(camera),cameraPath)
            records.append(.init(sourceID:asset.reference.id,photoID:asset.photo.id,roomID:asset.photo.roomID,roomName:asset.roomName,number:asset.photo.number,imageFile:jpegPath,cameraFile:cameraPath))
        }
        try write(encoder.encode(records),"photo-index.json")
        let readme = AppLanguage.text("Selected photos only. Folders: Photos/building/level/room. Same-name rooms receive a numbered suffix. Original photo numbers and camera poses are preserved in photo-index.json and camera files. Scan coordinates are not GPS. Device validation pending.",locale:locale)
        try write(Data((readme+"\n").utf8),"README.txt")
        try JSONSerialization.data(withJSONObject:["schemaVersion":1,"projectID":project.id.uuidString,"selection":true,"deviceValidationPending":true,"items":items],options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("manifest.json"),options:.atomic)
        try ExportManifestValidation.validate(in:root)
    }
}

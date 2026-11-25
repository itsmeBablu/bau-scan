import Foundation
import UniformTypeIdentifiers

/// Structured package export: generates a clean, organized handoff archive
/// following a single declarative layout table.
enum OrganisedExportService {
    enum Category: String, CaseIterable, Identifiable {
        case plans = "Plans"
        case models = "Models"
        case technicalRoom = "Utility room"
        case photos = "Photos"
        case studio = "Design Studio"
        case native = "Native packages"

        var id: String { rawValue }
    }

    struct Options {
        var includePlans = true
        var includeModels = true
        var includeTechnicalRoom = true
        var technicalRoomID: UUID? = nil
        var additionalTechnicalRoomIDs: Set<UUID> = []
        var includePhotos = true
        var removePhotoMetadata = false
        var includeStudio = true
        var includeNativePackages = false
        var includeIFC = false
        var includeArchitectureIFC = true
        var photosOnly = false
        var unit: MeasurementUnit = .both
        var locale: Locale = AppLanguage.locale
    }

    struct Manifest: Codable {
        var appName = Bundle.main.object(forInfoDictionaryKey:"CFBundleDisplayName") as? String ?? Bundle.main.object(forInfoDictionaryKey:"CFBundleName") as? String ?? "dWalkScan"
        var appVersion = Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "unknown"
        let schemaVersion = 1
        let createdAt: Date
        let subjectName: String
        let accuracyNote = "Device validation pending. Measurements and camera poses are scan coordinates, not GPS."
        var items: [ManifestItem]
        var sourceID: UUID? = nil
        var technicalRoomIDs: [UUID]? = nil
        var coordinateSystem: String? = nil
        var units: String? = nil
        var omissions: [String]? = nil
    }

    struct ManifestItem: Codable {
        let path: String
        let format: String
        let category: String
        let bytes: Int64
        var sha256: String? = nil
    }

    private struct TableRow {
        let category: Category
        let relativeFolder: String
        let filename: String
        let work: (URL) async throws -> Int64
    }

    /// Builds the organized ZIP archive at `destinationURL`.
    static func export(
        subject: ExportSubject,
        options: Options,
        storageRoot: URL,
        progressHandler: ((Double, String) -> Void)? = nil,
        to destinationURL: URL
    ) async throws {
        guard !options.includeNativePackages || !options.removePhotoMetadata else { throw CocoaError(.fileWriteInvalidFileName) }
        let stagingDir = FileManager.default.temporaryDirectory.appendingPathComponent("organised-export-" + UUID().uuidString, isDirectory: true)
        let archiveStem = ArchivePath.component(subject.name, fallback: "Export")
        let root = stagingDir.appendingPathComponent(archiveStem, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: stagingDir) }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        progressHandler?(0.05, AppLanguage.text("Building declarative layout…",locale:options.locale))

        // 1. Gather photo assets and determine structure
        let packageURL = subject.sourcePackageURL
        var photosList: [SurveyPhotoExportSource] = []
        if (options.includePhotos || options.photosOnly),let packageURL {
            photosList = try SurveyPhotoExportSource.list(from:packageURL,house:subject.house)
        }

        // 2. Only an explicit user selection may include a technical survey.
        var technicalPackages: [TechnicalRoomPackage] = []
        var retainedTechnicalBytes = 0
        let selectedTechnicalIDs = selectedTechnicalRoomIDs(options:options)
        guard selectedTechnicalIDs.count <= 20 else { throw CocoaError(.fileReadTooLarge) }
        for id in selectedTechnicalIDs {
            try Task.checkCancellation()
            let url = storageRoot.appendingPathComponent("TechnicalRooms").appendingPathComponent(id.uuidString).appendingPathExtension("technicalroom")
            let package = try TechnicalRoomPackage.read(from:url)
            guard package.manifest.id == id else { throw CocoaError(.fileReadCorruptFile) }
            let bytes = package.journal.snapshotBytes + package.evidence.bytes + package.document.photoAssets.reduce(0) { $0 + $1.jpegData.count }
            guard bytes <= 256 * 1_048_576-retainedTechnicalBytes else { throw CocoaError(.fileReadTooLarge) }
            retainedTechnicalBytes += bytes
            technicalPackages.append(package)
        }

        // 3. Locate matching studio design if any
        var studioDoc: SceneEditDocument? = nil
        let designURL = storageRoot.appendingPathComponent("SceneEdits/\(subject.kind == .house ? "house" : "room")-\(subject.id.uuidString).json")
        if FileManager.default.fileExists(atPath: designURL.path) {
            studioDoc = try SceneEditStore.read(designURL,source:subject.kind == .house ? .house : .room,id:subject.id)
        }

        // 4. Construct declarative layout table
        var table: [TableRow] = []

        if !options.photosOnly {
            if options.includeIFC {
                if options.includeArchitectureIFC {
                    table.append(TableRow(category:.models,relativeFolder:"bim",filename:"architecture.ifc") { target in
                        var settings = RevitExportOptions(); settings.includeMEP = false
                        let data = try RevitIFCExporter.export(house:subject.house,options:settings)
                        try data.write(to:target); return Int64(data.count)
                    })
                }
                for tech in technicalPackages {
                    table.append(TableRow(category:.technicalRoom,relativeFolder:"bim",filename:tech.manifest.id.uuidString+".ifc") { target in
                        var settings = RevitExportOptions(); settings.includeArchitecture = false
                        let data = try RevitIFCExporter.export(house:nil,technicalRooms:[.init(name:tech.manifest.name,document:tech.document)],options:settings)
                        try data.write(to:target); return Int64(data.count)
                    })
                }
            }
            if options.includeNativePackages {
                var sources: [(URL,String)] = []
                if let source = subject.sourcePackageURL {
                    let storedID = subject.kind == .house ? try HousePackage.readRecord(from:source).id : try RoomPackage.readRecord(from:source).id
                    guard storedID == subject.id else { throw CocoaError(.fileReadCorruptFile) }
                    sources.append((source,subject.id.uuidString+(subject.kind == .house ? ".housescan" : ".roomscan")))
                } else { throw CocoaError(.fileNoSuchFile) }
                for id in selectedTechnicalIDs {
                    sources.append((storageRoot.appendingPathComponent("TechnicalRooms/"+id.uuidString+".technicalroom"),id.uuidString+".technicalroom"))
                }
                let snapshots = stagingDir.appendingPathComponent("native-snapshots")
                try FileManager.default.createDirectory(at:snapshots,withIntermediateDirectories:true)
                for (source,name) in sources {
                    let snapshot = snapshots.appendingPathComponent(name)
                    try NativeExportSnapshot.copy(from:source,to:snapshot)
                    for path in try NativeExportSnapshot.files(in:snapshot) {
                        let relative = "native/"+name+"/"+path
                        table.append(TableRow(category:.native,relativeFolder:(relative as NSString).deletingLastPathComponent,filename:(path as NSString).lastPathComponent) { target in
                            try FileManager.default.copyItem(at:snapshot.appendingPathComponent(path),to:target)
                            return Int64(try target.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)
                        })
                    }
                }
            }
            if options.includePlans || options.includeModels || options.includeIFC {
                table.append(TableRow(category:.models,relativeFolder:"data",filename:"resolved-geometry.json") { target in
                    let data = try ResolvedGeometryExporter.data(for:subject.house,sourceID:subject.id)
                    try data.write(to:target); return Int64(data.count)
                })
            }
            // Plans
            if options.includePlans {
                let house = subject.house
                if house.stories.count > 1 {
                    for story in house.stories.sorted(by: { $0.index < $1.index }) {
                        let levelHouse = House(id: house.id, name: house.name, stories: [story])
                        let storyName = "level-\(story.index)"
                        table.append(TableRow(category: .plans, relativeFolder: "plans", filename: "\(storyName).pdf") { target in
                            var service = ExportService(locale: options.locale, unit: options.unit)
                            let data = try service.data(for: levelHouse, format: .pdf, title: "\(subject.name) - \(storyName)")
                            try data.write(to: target)
                            return Int64(data.count)
                        })
                        table.append(TableRow(category: .plans, relativeFolder: "plans", filename: "\(storyName).svg") { target in
                            let data = SVGExporter(locale: options.locale, unit: options.unit).data(for: levelHouse)
                            try data.write(to: target)
                            return Int64(data.count)
                        })
                        table.append(TableRow(category: .plans, relativeFolder: "plans", filename: "\(storyName).dxf") { target in
                            let dxf = DXFExporter(locale: options.locale, unit: options.unit).dxf(for: levelHouse)
                            let data = DXFTextEncoding.data(dxf)
                            try data.write(to: target)
                            return Int64(data.count)
                        })
                    }
                } else {
                    let levelHouse = house
                    table.append(TableRow(category: .plans, relativeFolder: "plans", filename: "plan.pdf") { target in
                        var service = ExportService(locale: options.locale, unit: options.unit)
                        let data = try service.data(for: levelHouse, format: .pdf, title: subject.name)
                        try data.write(to: target)
                        return Int64(data.count)
                    })
                    table.append(TableRow(category: .plans, relativeFolder: "plans", filename: "plan.svg") { target in
                        let data = SVGExporter(locale: options.locale, unit: options.unit).data(for: levelHouse)
                        try data.write(to: target)
                        return Int64(data.count)
                    })
                    table.append(TableRow(category: .plans, relativeFolder: "plans", filename: "plan.dxf") { target in
                        let dxf = DXFExporter(locale: options.locale, unit: options.unit).dxf(for: levelHouse)
                        let data = DXFTextEncoding.data(dxf)
                        try data.write(to: target)
                        return Int64(data.count)
                    })
                }
            }

            // Models
            if options.includeModels {
                let house = subject.house
                for story in house.stories.sorted(by: { $0.index < $1.index }) {
                    let levelHouse = House(id: house.id, name: house.name, stories: [story])
                    let prefix = house.stories.count > 1 ? "level-\(story.index)" : "model"
                    let mesh = PlanMeshBuilder().build(levelHouse)

                    table.append(TableRow(category: .models, relativeFolder: "models", filename: "\(prefix).obj") { target in
                        let data = MeshWriters.obj(mesh, name: subject.name)
                        try data.write(to: target)
                        return Int64(data.count)
                    })
                    table.append(TableRow(category: .models, relativeFolder: "models", filename: "\(prefix).stl") { target in
                        let data = MeshWriters.stl(mesh, name: subject.name)
                        try data.write(to: target)
                        return Int64(data.count)
                    })
                    table.append(TableRow(category: .models, relativeFolder: "models", filename: "\(prefix).ply") { target in
                        let data = MeshWriters.ply(mesh, name: subject.name)
                        try data.write(to: target)
                        return Int64(data.count)
                    })
                    if let usdzURL = subject.usdzURL, FileManager.default.fileExists(atPath: usdzURL.path) {
                        table.append(TableRow(category: .models, relativeFolder: "models", filename: "\(prefix).usdz") { target in
                            try FileManager.default.copyItem(at: usdzURL, to: target)
                            let attr = try FileManager.default.attributesOfItem(atPath: target.path)
                            return (attr[.size] as? NSNumber)?.int64Value ?? 0
                        })
                    }
                }
            }

            // Technical Room
            for tech in technicalPackages {
                let technicalFolder = technicalPackages.count == 1 ? "technical-room" : "technical-rooms/"+ArchivePath.component(tech.manifest.name)+"-"+tech.manifest.id.uuidString
                table.append(TableRow(category: .technicalRoom, relativeFolder: technicalFolder, filename: "technical-room-v1.json") { target in
                    let data = try TechnicalRoomJSONExporter.handoff(for: tech)
                    try data.write(to: target)
                    return Int64(data.count)
                })
                table.append(TableRow(category:.technicalRoom,relativeFolder:technicalFolder,filename:"survey-details.json") { target in
                    try TechnicalMeshExporter.write(tech,format:.json,to:target)
                    return Int64(try target.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)
                })
                if options.includePhotos {
                    let images = SurveyPhotoStore.images(technical:tech)
                    let entries = images.map { image in
                        OrganisedPhotoIndex.Entry(photo:image.photo,room:tech.manifest.name,story:nil,number:image.photo.number,
                            path:technicalFolder+"/photos/"+String(format:"photo-%02lld.jpg",Int64(image.photo.number)))
                    }
                    for (image,entry) in zip(images,entries) {
                        table.append(TableRow(category:.photos,relativeFolder:technicalFolder+"/photos",filename:URL(fileURLWithPath:entry.path).lastPathComponent) { target in
                            try image.photo.validate()
                            try image.jpegData.write(to:target)
                            return options.removePhotoMetadata ? try PhotoExportPrivacy.removeMetadata(fromCopyAt:target) : Int64(image.jpegData.count)
                        })
                    }
                    for asset in tech.document.photoAssets {
                        table.append(TableRow(category:.photos,relativeFolder:technicalFolder+"/attachments",filename:asset.id.uuidString+".jpg") { target in
                            try asset.jpegData.write(to:target)
                            return options.removePhotoMetadata ? try PhotoExportPrivacy.removeMetadata(fromCopyAt:target) : Int64(asset.jpegData.count)
                        })
                    }
                    table.append(TableRow(category:.photos,relativeFolder:technicalFolder,filename:"photo-index.json") { target in
                        let records = try OrganisedPhotoIndex.records(entries,sourceID:tech.manifest.id,root:root)
                        let attachments: [[String:Any]] = try tech.document.photoAssets.map { asset in
                            let path = technicalFolder+"/attachments/"+asset.id.uuidString+".jpg"
                            let file = root.appendingPathComponent(path)
                            return ["photoID":asset.id.uuidString,"sourceID":tech.manifest.id.uuidString,"path":path,
                                "originalReference":tech.document.room.photos.first(where:{ $0.id == asset.id }).map { $0.reference.value as Any } ?? NSNull(),
                                "equipmentIDs":tech.document.room.equipment.filter { $0.photoRefs.contains(asset.id) }.map { $0.id.uuidString },
                                "bytes":try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0,"sha256":try ExportChecksum.sha256(file),
                                "cameraPose":NSNull(),"accuracyMm":NSNull(),"deviceValidationPending":true]
                        }
                        let data = try JSONSerialization.data(withJSONObject:["schemaVersion":1,"photos":records,"attachments":attachments],options:[.prettyPrinted,.sortedKeys])
                        try data.write(to:target); return Int64(data.count)
                    })
                }
                if !tech.journal.meshes.isEmpty {
                table.append(TableRow(category: .technicalRoom, relativeFolder: technicalFolder, filename: "mesh.obj") { target in
                    try TechnicalMeshExporter.write(tech, format: .obj, to: target)
                    let attr = try FileManager.default.attributesOfItem(atPath: target.path)
                    return (attr[.size] as? NSNumber)?.int64Value ?? 0
                })
                table.append(TableRow(category: .technicalRoom, relativeFolder: technicalFolder, filename: "survey.dxf") { target in
                    try TechnicalMeshExporter.write(tech, format: .dxf, to: target)
                    let attr = try FileManager.default.attributesOfItem(atPath: target.path)
                    return (attr[.size] as? NSNumber)?.int64Value ?? 0
                })
                }
            }

            // Studio Design
            if options.includeStudio, let studio = studioDoc {
                table.append(TableRow(category: .studio, relativeFolder: "studio", filename: "design.json") { target in
                    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try enc.encode(studio)
                    try data.write(to: target)
                    return Int64(data.count)
                })
                table.append(TableRow(category: .studio, relativeFolder: "studio", filename: "engineering.csv") { target in
                    let csv = studio.engineeringCSV()
                    try csv.write(to: target)
                    let attr = try FileManager.default.attributesOfItem(atPath: target.path)
                    return (attr[.size] as? NSNumber)?.int64Value ?? 0
                })
            }
        }

        // Photos & Photo Index
        if options.includePhotos || options.photosOnly {
            if !photosList.isEmpty {
                var entries: [OrganisedPhotoIndex.Entry] = [],aliases: [String:String] = [:],usedAliases = Set<String>(),numbers: [String:Int] = [:]
                for item in photosList {
                    let story = subject.house.allRooms.first { $0.id == item.photo.roomID }?.story
                    let level = story.map { "level-\($0)" } ?? "unassigned"
                    let identity = level+"|"+(item.photo.roomID?.uuidString ?? "unassigned")
                    let room: String
                    if let alias = aliases[identity] { room = alias }
                    else {
                        let base = ArchivePath.component(item.roomName,fallback:"room")
                        var candidate = base,n = 2
                        while usedAliases.contains((level+"/"+candidate).lowercased()) { candidate = base+" \(n)"; n += 1 }
                        usedAliases.insert((level+"/"+candidate).lowercased()); aliases[identity] = candidate; room = candidate
                    }
                    numbers[identity,default:0] += 1
                    let number = numbers[identity] ?? 1,folder = "photos/"+level+"/"+room
                    let filename = String(format:"photo-%02lld.jpg",Int64(number))
                    entries.append(.init(photo:item.photo,room:room,story:story,number:number,path:folder+"/"+filename))
                    table.append(TableRow(category:.photos,relativeFolder:folder,filename:filename) { target in
                        let bytes = try item.copy(to:target)
                        return options.removePhotoMetadata ? try PhotoExportPrivacy.removeMetadata(fromCopyAt:target) : bytes
                    })
                }
                let indexEntries = entries
                table.append(TableRow(category:.photos,relativeFolder:"photos",filename:"index.json") { target in
                    let records = try OrganisedPhotoIndex.records(indexEntries,sourceID:subject.id,root:root)
                    let data = try JSONSerialization.data(withJSONObject:["schemaVersion":1,"photos":records],options:[.prettyPrinted,.sortedKeys])
                    try data.write(to:target); return Int64(data.count)
                })
                table.append(TableRow(category:.photos,relativeFolder:"photos",filename:"index.csv") { target in
                    let records = try OrganisedPhotoIndex.records(indexEntries,sourceID:subject.id,root:root)
                    let data = OrganisedPhotoIndex.csv(records)
                    try data.write(to:target); return Int64(data.count)
                })
            }
        }

        // 5. Execute table entries with progress
        var manifestItems: [ManifestItem] = []
        let total = Double(table.count)
        for (i, row) in table.enumerated() {
            try Task.checkCancellation()
            let progress = 0.1 + (Double(i) / max(total, 1)) * 0.75
            progressHandler?(progress, AppLanguage.format("Exporting %@…",[row.filename],locale:options.locale))
            let folderURL = root.appendingPathComponent(row.relativeFolder, isDirectory: true)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let fileURL = folderURL.appendingPathComponent(row.filename)
            let bytes = try await row.work(fileURL)
            manifestItems.append(ManifestItem(
                path: "\(row.relativeFolder)/\(row.filename)",
                format: fileURL.pathExtension.uppercased(),
                category: row.category.rawValue,
                bytes: bytes,
                sha256: try ExportChecksum.sha256(fileURL)
            ))
        }

        // 6. Write manifest.json
        var manifest = Manifest(createdAt:Date(),subjectName:subject.name,items:manifestItems)
        manifest.sourceID = subject.id; manifest.technicalRoomIDs = selectedTechnicalIDs
        manifest.coordinateSystem = "Architectural plan X,-Z; mesh Y-up metres; technical detail includes original-frame alignment. No GPS."
        manifest.units = "Geometry: metres; SVG: millimetres; labelled dimensions: "+options.unit.rawValue
        manifest.omissions = []
        manifest.omissions?.append(options.removePhotoMetadata ? "Export JPEG copies were re-encoded without source EXIF/GPS/IPTC metadata; image compression may change. Survey camera poses remain in the indexes." : "Original photo metadata is preserved and may contain private information. Survey indexes include camera poses.")
        if options.includeTechnicalRoom && !options.photosOnly && selectedTechnicalIDs.isEmpty { manifest.omissions?.append("No technical survey was explicitly selected.") }
        for tech in technicalPackages where tech.journal.meshes.isEmpty { manifest.omissions?.append("Technical survey \(tech.manifest.id): no captured mesh; OBJ and mesh DXF omitted.") }
        if !options.includeNativePackages { manifest.omissions?.append("Native backups were not selected.") }
        manifest.omissions?.append("Voice audio is not included. Technical selections are handoff selections, not verified spatial registration to the house. Technical IFC files use separate room frames; they are not a combined registered building.")
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: root.appendingPathComponent("manifest.json"))

        // 7. Write README.txt
        let readmeText = buildReadme(subject: subject, options: options, manifest: manifest)
        try readmeText.data(using: .utf8)?.write(to: root.appendingPathComponent("README.txt"))

        // 8. ZIP compression
        progressHandler?(0.90, AppLanguage.text("Compressing ZIP archive…",locale:options.locale))
        let archive = stagingDir.appendingPathComponent("completed.zip")
        try Task.checkCancellation()
        try ArchiveExporter.zip(directory:root,to:archive)
        try Task.checkCancellation()
        let staged = try PackageReplacement.staging(for:destinationURL)
        defer { try? FileManager.default.removeItem(at:staged) }
        try FileManager.default.copyItem(at:archive,to:staged)
        try Task.checkCancellation()
        try RoomPackage.coordinatedWrite(at:destinationURL,options:.forReplacing) { try PackageReplacement.commit(staged,to:$0) }
        progressHandler?(1.0, AppLanguage.text("Export completed.",locale:options.locale))
    }

    private static func buildReadme(subject: ExportSubject, options: Options, manifest: Manifest) -> String {
        let df = DateFormatter(); df.locale = options.locale; df.dateStyle = .medium; df.timeStyle = .short
        var s = "\(manifest.appName) \(manifest.appVersion) — Organised Project Export\n"
        s += "====================================\n\n"
        s += "Project: \(subject.name)\n"
        s += "Created: \(df.string(from: Date()))\n"
        s += "Units: \(options.unit.shortLabel)\n"
        s += "Accuracy: Device validation pending. All coordinates are scan relative, no GPS.\n\n"
        s += AppLanguage.text("export.manifest.checksums",locale:options.locale)+"\n\n"
        for omission in manifest.omissions ?? [] { s += "Omission / limitation: "+omission+"\n" }
        s += "CONTENTS:\n"
        for item in manifest.items {
            s += "  - \(item.path) [\(item.format)] (\(item.bytes / 1024) KB)\n"
        }
        s += "\n---\nExported with dWalkScan by BabuReddy.\n"
        return s
    }

    /// Estimated total size in bytes for given configuration.
    static func estimateSize(subject: ExportSubject, options: Options, storageRoot: URL) -> Int64 {
        var size: Int64 = 0
        if !options.photosOnly {
            if options.includePlans { size += 1_500_000 }
            if options.includeModels { size += 6_000_000 }
            size += Int64(selectedTechnicalRoomIDs(options:options).count)*3_500_000
            if options.includeIFC { size += 1_000_000 }
            if options.includeStudio { size += 2_000_000 }
        }
        if options.includePhotos || options.photosOnly {
            if let packageURL = subject.sourcePackageURL {
                let photos = (try? SurveyPhotoExportSource.list(from:packageURL,house:subject.house)) ?? []
                size += Int64(photos.reduce(0) { $0+$1.byteCount })
            }
        }
        return size
    }
    static func technicalRoomURL(options: Options,storageRoot: URL) -> URL? {
        guard options.includeTechnicalRoom,!options.photosOnly,let id = options.technicalRoomID else { return nil }
        return storageRoot.appendingPathComponent("TechnicalRooms").appendingPathComponent(id.uuidString).appendingPathExtension("technicalroom")
    }
    static func selectedTechnicalRoomIDs(options: Options) -> [UUID] {
        guard options.includeTechnicalRoom,!options.photosOnly else { return [] }
        return options.additionalTechnicalRoomIDs.union(options.technicalRoomID.map { [$0] } ?? []).sorted { $0.uuidString < $1.uuidString }
    }
}

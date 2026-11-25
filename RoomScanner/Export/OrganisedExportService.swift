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

        var id: String { rawValue }
    }

    struct Options {
        var includePlans = true
        var includeModels = true
        var includeTechnicalRoom = true
        var technicalRoomID: UUID? = nil
        var includePhotos = true
        var includeStudio = true
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
        var technicalPackage: TechnicalRoomPackage? = nil
        if let url = technicalRoomURL(options:options,storageRoot:storageRoot),let id = options.technicalRoomID {
            let package = try TechnicalRoomPackage.read(from:url)
            guard package.manifest.id == id else { throw CocoaError(.fileReadCorruptFile) }
            technicalPackage = package
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
            if options.includePlans || options.includeModels {
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
            if options.includeTechnicalRoom, let tech = technicalPackage {
                table.append(TableRow(category: .technicalRoom, relativeFolder: "technical-room", filename: "technical-room-v1.json") { target in
                    let data = try TechnicalRoomJSONExporter.handoff(for: tech)
                    try data.write(to: target)
                    return Int64(data.count)
                })
                table.append(TableRow(category: .technicalRoom, relativeFolder: "technical-room", filename: "mesh.obj") { target in
                    try TechnicalMeshExporter.write(tech, format: .obj, to: target)
                    let attr = try FileManager.default.attributesOfItem(atPath: target.path)
                    return (attr[.size] as? NSNumber)?.int64Value ?? 0
                })
                table.append(TableRow(category: .technicalRoom, relativeFolder: "technical-room", filename: "survey.dxf") { target in
                    try TechnicalMeshExporter.write(tech, format: .dxf, to: target)
                    let attr = try FileManager.default.attributesOfItem(atPath: target.path)
                    return (attr[.size] as? NSNumber)?.int64Value ?? 0
                })
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
                var photoRows: [String] = ["number,level,room,file,timestamp,pos_x,pos_y,pos_z,yaw,pitch,roll"]
                for (idx, item) in photosList.enumerated() {
                    let roomClean = ArchivePath.component(item.roomName, fallback: "room")
                    let storyIdx = subject.house.allRooms.first(where: { $0.id == item.photo.roomID })?.story ?? 0
                    let levelClean = "level-\(storyIdx)"
                    let folder = "photos/\(levelClean)/\(roomClean)"
                    let photoNum = String(format: "photo-%02d.jpg", idx + 1)
                    let relativeFile = "\(folder)/\(photoNum)"

                    // Stream photo copy
                    table.append(TableRow(category: .photos, relativeFolder: folder, filename: photoNum) { target in
                        try item.copy(to:target)
                    })

                    // CSV row
                    let m = item.photo.viewingPose
                    let x = m.count > 12 ? m[12] : 0
                    let y = m.count > 13 ? m[13] : 0
                    let z = m.count > 14 ? m[14] : 0
                    let yaw = m.count > 10 ? atan2(m[8], m[10]) : 0
                    let pitch = m.count > 9 ? asin(-m[9]) : 0
                    let roll = m.count > 4 ? atan2(m[1], m[5]) : 0
                    let ts = item.photo.capturedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "\(item.photo.timestamp)"
                    photoRows.append("\(idx + 1),\(levelClean),\(roomClean),\(relativeFile),\(ts),\(String(format: "%.4f", x)),\(String(format: "%.4f", y)),\(String(format: "%.4f", z)),\(String(format: "%.4f", yaw)),\(String(format: "%.4f", pitch)),\(String(format: "%.4f", roll))")
                }

                // photos/index.csv
                table.append(TableRow(category: .photos, relativeFolder: "photos", filename: "index.csv") { target in
                    let csvData = Data(photoRows.joined(separator:"\n").utf8)
                    try csvData.write(to: target)
                    return Int64(csvData.count)
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
        let manifest = Manifest(createdAt: Date(), subjectName: subject.name, items: manifestItems)
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
            if options.includeTechnicalRoom { size += 3_500_000 }
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
}

import Foundation

/// Separate files prevent different levels being silently stacked onto the same plane.
enum LevelExportService {
    static let formats: Set<ExportFormat> = [.dxf,.svg,.obj,.stl,.ply]
    static func needsArchive(house: House, format: ExportFormat) -> Bool { house.stories.count > 1 && formats.contains(format) }
    static func elevations(house: House, scans: [ScanInput]) -> [Int:Double] {
        var result: [Int:Double] = [:]
        for story in house.stories {
            let ids = Set(story.rooms.map(\.id))
            let values = scans.filter { ids.contains($0.id) }.map { StoryDetector.floorHeight(of:$0) }.filter(\.isFinite).sorted()
            if !values.isEmpty { result[story.index] = values[values.count/2] }
        }
        return result
    }
    static func write(house: House, scans: [ScanInput], format: ExportFormat, locale: Locale, unit: MeasurementUnit, to destination: URL) throws {
        guard formats.contains(format) else { throw ExportService.ExportError.notAvailable(format) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let heights = elevations(house:house,scans:scans)
        var notes = [AppLanguage.text("One file per level. Geometry is in metres; SVG uses millimetres. Device validation pending.",locale:locale)]
        for story in house.stories.sorted(by:{ $0.index < $1.index }) {
            let level = House(id:house.id,name:house.name,stories:[story])
            let elevation = heights[story.index]
            notes.append("\(story.index): "+(elevation.map { MeasurementFormat.meters($0,locale:locale)+" — "+AppLanguage.text("Scan floor datum",locale:locale) } ?? AppLanguage.text("Elevation unavailable. This file uses its own local floor datum, not a verified building elevation.",locale:locale)))
            let data: Data
            switch format {
            case .dxf:
                var records = DXFExporter(locale:locale,unit:unit).dxf(for:level).components(separatedBy:"\n")
                if let elevation {
                    for i in stride(from:0,to:records.count-1,by:2) where ["30","31","32","38"].contains(records[i].trimmingCharacters(in:.whitespacesAndNewlines)) {
                        records[i+1] = String(format:"%.6f",locale:Locale(identifier:"en_US_POSIX"),elevation)
                    }
                }
                // R12 text is Windows-1252, matching the declared drawing code page.
                data = records.joined(separator:"\n").data(using:.windowsCP1252,allowLossyConversion:true) ?? Data()
            case .svg: data = SVGExporter(locale:locale,unit:unit).data(for:level)
            default:
                var mesh = PlanMeshBuilder().build(level)
                if let elevation { for i in mesh.positions.indices { mesh.positions[i].y += Float(elevation) } }
                switch format {
                case .obj: data = MeshWriters.obj(mesh,name:house.name)
                case .stl: data = MeshWriters.stl(mesh,name:house.name)
                case .ply: data = MeshWriters.ply(mesh,name:house.name)
                default: throw ExportService.ExportError.notAvailable(format)
                }
            }
            try data.write(to:directory.appendingPathComponent("level-\(story.index).\(format.fileExtension)"))
        }
        try notes.joined(separator:"\n").write(to:directory.appendingPathComponent("README.txt"),atomically:true,encoding:.utf8)
        try ArchiveExporter.zip(directory:directory,to:destination)
    }
}

import Foundation
import SceneKit
import SceneKit.ModelIO
import ModelIO

@MainActor enum StudioExporter {
    enum Format: String,CaseIterable { case project, usdz, obj, pdf, svg, dxf }
    static func data(_ document: SceneEditDocument,format: Format,story: Int? = nil) throws -> Data {
        try document.validate()
        if format == .project {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
            return try encoder.encode(document)
        }
        if [.pdf,.svg,.dxf].contains(format) {
            var exporter = ExportService(); exporter.unit = .meters
            let type: ExportFormat = format == .pdf ? .pdf : format == .svg ? .svg : .dxf
            return try exporter.data(for: document.plan,format: type,title: document.title+" · Edited design")
        }
        let folder = try ExportService.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        // Keep floors separate when captured elevations are unavailable in the plan model.
        let scene = StudioSceneBuilder.scene(document,story: story ?? document.shell.stories.first?.index,cutaway: false,decorated: false)
        if format == .usdz {
            let url = folder.appendingPathComponent("Edited-design.usdz")
            guard scene.write(to: url,options: nil,delegate: nil,progressHandler: nil) else { throw SceneEditDocument.Failure.exportFailed }
            return try Data(contentsOf: url)
        }
        let contents = folder.appendingPathComponent("Edited-design",isDirectory: true)
        try FileManager.default.createDirectory(at: contents,withIntermediateDirectories: true)
        let asset = MDLAsset(scnScene: scene,bufferAllocator: nil)
        guard MDLAsset.canExportFileExtension("obj") else { throw SceneEditDocument.Failure.exportFailed }
        try asset.export(to: contents.appendingPathComponent("Edited-design.obj"))
        try "Editable design representation; metres, Y up. Original scan evidence is not included. Materials are supplied alongside OBJ.\n".write(to: contents.appendingPathComponent("README.txt"),atomically: true,encoding: .utf8)
        let zip = folder.appendingPathComponent("Edited-design-OBJ.zip")
        try ArchiveExporter.zip(directory: contents,to: zip)
        return try Data(contentsOf: zip)
    }
}

import Foundation
import SceneKit
import SceneKit.ModelIO
import ModelIO
import os

@MainActor enum StudioExporter {
    enum Format: String,CaseIterable { case project, usdz, obj, pdf, svg, dxf, csv }
    static func dataAsync(_ document: SceneEditDocument,format: Format,story: Int? = nil) async throws -> Data {
        let signposter = OSSignposter(subsystem:"io.github.itsmebablu.dwalkscan",category:"StudioExport")
        let interval = signposter.beginInterval("StudioExport")
        defer { signposter.endInterval("StudioExport",interval) }
        let rawFormat = format.rawValue
        if !["usdz","obj"].contains(rawFormat) {
            return try await StudioExportPreparation.worker {
                guard let data = try StudioExportPreparation.data(document,format:rawFormat,story:story) else { throw SceneEditDocument.Failure.exportFailed }
                return data
            }
        }
        let folder = try await StudioExportPreparation.worker { try ExportService.scratchDirectory() }
        do {
            try await StudioExportPreparation.worker { try document.validate() }
            let scene = StudioSceneBuilder.scene(document,story:story ?? document.shell.stories.first?.index,cutaway:false,decorated:false)
            let data: Data
            if format == .usdz {
                let url = folder.appendingPathComponent("Edited-design.usdz")
                guard scene.write(to:url,options:nil,delegate:nil,progressHandler:nil) else { throw SceneEditDocument.Failure.exportFailed }
                data = try await StudioExportPreparation.worker { try Data(contentsOf:url) }
            } else {
                // This newly created Model I/O asset has a single worker owner after the bridge.
                let asset = MDLAsset(scnScene:scene,bufferAllocator:nil)
                data = try await StudioExportPreparation.worker {
                    let contents = folder.appendingPathComponent("Edited-design",isDirectory:true)
                    try FileManager.default.createDirectory(at:contents,withIntermediateDirectories:true)
                    guard MDLAsset.canExportFileExtension("obj") else { throw SceneEditDocument.Failure.exportFailed }
                    try asset.export(to:contents.appendingPathComponent("Edited-design.obj"))
                    try "Editable design representation; metres, Y up. Original scan evidence is not included. Materials are supplied alongside OBJ.\n".write(to:contents.appendingPathComponent("README.txt"),atomically:true,encoding:.utf8)
                    let zip = folder.appendingPathComponent("Edited-design-OBJ.zip")
                    try ArchiveExporter.zip(directory:contents,to:zip)
                    return try Data(contentsOf:zip)
                }
            }
            try await StudioExportPreparation.worker { try FileManager.default.removeItem(at:folder) }
            return data
        } catch {
            _ = try? await Task.detached { try FileManager.default.removeItem(at:folder) }.value
            throw error
        }
    }
    static func data(_ document: SceneEditDocument,format: Format,story: Int? = nil) throws -> Data {
        if let data = try StudioExportPreparation.data(document,format:format.rawValue,story:story) { return data }
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

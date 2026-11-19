import Foundation
import ModelIO

/// Converts a Model I/O readable 3D file (USDZ/USD scan) to OBJ, STL, or
/// PLY. Model I/O imports USDZ and exports these formats on iOS and macOS,
/// but cannot export USDZ directly. Call off main thread.
enum ModelIOConverter {
    enum ConversionError: LocalizedError {
        case unsupported(String), emptyAsset
        var errorDescription: String? {
            switch self {
            case .unsupported(let ext): "Model I/O ne peut pas écrire « .\(ext) »."
            case .emptyAsset: "Le fichier 3D source ne contient aucun maillage."
            }
        }
    }

    static func canExport(_ format: ExportFormat) -> Bool { MDLAsset.canExportFileExtension(format.fileExtension) }

    static func convert(_ source: URL, to destination: URL) throws {
        let ext = destination.pathExtension
        guard MDLAsset.canExportFileExtension(ext) else { throw ConversionError.unsupported(ext) }
        let asset = MDLAsset(url: source)
        guard asset.count > 0 else { throw ConversionError.emptyAsset }
        try? FileManager.default.removeItem(at: destination)
        try asset.export(to: destination)
    }
}

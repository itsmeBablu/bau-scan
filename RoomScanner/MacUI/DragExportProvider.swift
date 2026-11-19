import AppKit
import UniformTypeIdentifiers

/// Drag-and-drop to other apps: file generated on demand when destination requests it.
/// destination requests it (`registerFileRepresentation`), never before.
enum DragExportProvider {
    /// Provider of an on-the-fly generated export (PDF to Preview, DXF to LibreCAD, etc.).
    static func provider(subject: ExportSubject, format: ExportFormat) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = ExportService.fileName(for: subject, format: format)
        provider.registerFileRepresentation(forTypeIdentifier: format.utType.identifier, fileOptions: [], visibility: .all) { completion in
            do {
                let url = try ExportService().export(subject, format: format)
                completion(url, false, nil)
            } catch {
                completion(nil, false, error)
            }
            return nil
        }
        return provider
    }

    /// Provider of the `.roomscan` / `.housescan` document package (Finder, AirDrop, Mail).
    static func packageProvider(url: URL) -> NSItemProvider {
        let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
        provider.suggestedName = url.lastPathComponent
        return provider
    }
}

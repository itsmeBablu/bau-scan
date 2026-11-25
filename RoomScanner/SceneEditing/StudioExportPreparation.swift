import Foundation

enum StudioExportPreparation {
    static func data(_ document: SceneEditDocument,format: String,story: Int?) throws -> Data? {
        try document.validate()
        if format == "csv" { return document.engineeringCSV() }
        if format == "project" {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
            return try encoder.encode(document)
        }
        guard ["pdf","svg","dxf"].contains(format) else { return nil }
        var exporter = ExportService(); exporter.unit = .meters
        let type: ExportFormat = format == "pdf" ? .pdf : format == "svg" ? .svg : .dxf
        let plan = document.plan
        let shown = type == .pdf ? plan : House(id:plan.id,name:plan.name,stories:plan.stories.filter { $0.index == (story ?? plan.stories.first?.index) })
        return try exporter.data(for:shown,format:type,title:document.title+" · "+AppLanguage.text(document.engineering?.view.rawValue ?? "all")+" · "+AppLanguage.text("Edited design"))
    }
    static func worker<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        let task = Task.detached(priority:.userInitiated,operation:operation)
        return try await withTaskCancellationHandler(operation:{ try await task.value },onCancel:{ task.cancel() })
    }
}

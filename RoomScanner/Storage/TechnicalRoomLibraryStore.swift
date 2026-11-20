import Foundation
import Observation

@MainActor @Observable final class TechnicalRoomLibraryStore {
    let root: URL
    private(set) var records: [TechnicalRoomManifest] = []
    private(set) var loadWarnings: [String] = []
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("TechnicalRooms", isDirectory: true)
    }
    func url(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString).appendingPathExtension("technicalroom") }
    func reload() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var found: [TechnicalRoomManifest] = [], warnings = recoverInterruptedReplacements()
        for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) where url.pathExtension == "technicalroom" {
            do {
                let record = try TechnicalRoomPackage.readManifest(from: url)
                guard url.deletingPathExtension().lastPathComponent == record.id.uuidString else { throw TechnicalRoomPackage.PackageError.invalidPackage }
                found.append(record)
            } catch { warnings.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        records = found.sorted { $0.modifiedAt > $1.modifiedAt }; loadWarnings = warnings
    }
    private func recoverInterruptedReplacements() -> [String] {
        var warnings: [String] = []
        let items = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for backup in items where backup.lastPathComponent.hasPrefix(".technical-backup-") {
            do {
                let package = try TechnicalRoomPackage.read(from: backup)
                let target = url(for: package.manifest.id)
                guard !FileManager.default.fileExists(atPath: target.path) else { continue }
                try FileManager.default.moveItem(at: backup, to: target)
                warnings.append("Recovered the previous saved version of \(package.manifest.name) after an interrupted replacement.")
            } catch { warnings.append("A recovery backup was retained for manual inspection: \(backup.lastPathComponent). \(error.localizedDescription)") }
        }
        return warnings
    }
    func save(_ package: TechnicalRoomPackage) async throws {
        let target = url(for: package.manifest.id)
        try await Task.detached(priority: .userInitiated) { try package.write(to: target) }.value
        try reload()
    }
    func read(_ id: UUID) async throws -> TechnicalRoomPackage {
        let target = url(for: id)
        return try await Task.detached(priority: .userInitiated) { try TechnicalRoomPackage.read(from: target) }.value
    }
    func importPackage(_ source: URL) async throws -> UUID {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        var package = try await Task.detached(priority: .userInitiated) { try TechnicalRoomPackage.read(from: source) }.value
        if source.resolvingSymlinksInPath().standardizedFileURL == url(for: package.manifest.id).resolvingSymlinksInPath().standardizedFileURL {
            try reload()
            return package.manifest.id
        }
        if FileManager.default.fileExists(atPath: url(for: package.manifest.id).path) {
            let id = UUID(); package.manifest.id = id; package.document.room.id = id; package.manifest.name += " (Imported)"
        }
        package.manifest.modifiedAt = Date()
        try await save(package)
        return package.manifest.id
    }
    func delete(_ id: UUID) throws {
        let target = url(for: id)
        // Recoverable deletion: move this one validated library item to a private library trash.
        let trash = root.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: target, to: trash.appendingPathComponent("\(id)-\(UUID()).technicalroom"))
        try reload()
    }
}

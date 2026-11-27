import Foundation

/// Transient catalogue only. Root precedence and source kind are part of the
/// lookup contract; no scan or Studio document is rewritten while browsing.
enum SceneEditCatalogue {
    struct Entry: Identifiable {
        let document: SceneEditDocument
        let root: URL
        var id: String { DesignRef(document).id }
    }

    static func load(roots: [URL]) throws -> [Entry] {
        var entries: [Entry] = []
        var seen = Set<String>()
        for documents in roots {
            try Task.checkCancellation()
            let directory = documents.appendingPathComponent("SceneEdits", isDirectory: true)
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.prefix(200)
            for file in files {
                try Task.checkCancellation()
                let name = file.deletingPathExtension().lastPathComponent
                guard let separator = name.firstIndex(of: "-"),
                      let source = SceneEditDocument.Source(rawValue: String(name[..<separator])),
                      let id = UUID(uuidString: String(name[name.index(after: separator)...])),
                      let document = try SceneEditStore.read(file, source: source, id: id) else { continue }
                let entry = Entry(document: document, root: documents)
                if seen.insert(entry.id).inserted { entries.append(entry) }
            }
        }
        return entries.sorted {
            let order = $0.document.title.localizedStandardCompare($1.document.title)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}

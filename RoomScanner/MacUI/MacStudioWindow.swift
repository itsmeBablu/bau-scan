import SwiftUI

/// Native multi-window container for Studio on macOS.
struct MacStudioWindow: View {
    let designID: UUID
    @Environment(RoomStore.self) private var store
    @State private var document: SceneEditDocument?
    @State private var storageRoot: URL?
    @State private var error: String?

    var body: some View {
        Group {
            if let document, let storageRoot {
                StudioProjectView(seed: document, storageRoot: storageRoot)
            } else if let error {
                ContentUnavailableView("Could not open design", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView("Opening Studio…")
            }
        }
        .frame(minWidth: 900, minHeight: 650)
        .task(id: designID.uuidString+store.location.documentsURL.path) {
            document = nil; storageRoot = nil; error = nil
            await load()
        }
    }

    private func load() async {
        let primary = store.location,local = StorageLocation.local()
        let locations = store.allowsCloud && primary != local ? [primary,local] : [primary]
        for location in locations {
            let root = location.documentsURL
            for source in [SceneEditDocument.Source.house, .room, .technical] {
                let url = SceneEditStore.url(root:root,source:source,id:designID)
                if FileManager.default.fileExists(atPath: url.path) {
                    do {
                        if let doc = try SceneEditStore.read(url, source: source, id: designID) {
                            guard !Task.isCancelled,primary == store.location else { return }
                            storageRoot = root; document = doc
                            return
                        }
                    } catch {
                        if !Task.isCancelled { self.error = error.localizedDescription }
                    }
                }
            }
        }
        if document == nil && error == nil {
            error = AppLanguage.text("Design not found.")
        }
    }
}

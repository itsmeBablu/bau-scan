import SwiftUI

/// Native multi-window container for Studio on macOS.
struct MacStudioWindow: View {
    let designID: UUID
    @Environment(RoomStore.self) private var store
    @State private var document: SceneEditDocument?
    @State private var storageURL: URL?
    @State private var photos: [SurveyPhotoImage] = []
    @State private var error: String?

    var body: some View {
        Group {
            if let document, let storageURL {
                StudioEditorView(document: document, storageURL: storageURL, photos: photos)
            } else if let error {
                ContentUnavailableView("Could not open design", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView("Opening Studio…")
            }
        }
        .frame(minWidth: 900, minHeight: 650)
        .task(id: designID.uuidString+store.location.documentsURL.path) {
            document = nil; storageURL = nil; error = nil; photos = []
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
                            let loadedPhotos: [SurveyPhotoImage] = (try? await Task.detached { () throws -> [SurveyPhotoImage] in
                                if source == .technical {
                                    let techURL = root.appendingPathComponent("TechnicalRooms").appendingPathComponent(designID.uuidString).appendingPathExtension("technicalroom")
                                    return SurveyPhotoStore.images(technical: try TechnicalRoomPackage.read(from: techURL), studio: true)
                                }
                                let pkg = source == .house
                                    ? location.housePackageURL(for:designID)
                                    : location.packageURL(for:designID)
                                return try SurveyPhotoStore.images(from: pkg, house: doc.shell)
                            }.value) ?? []
                            guard !Task.isCancelled,primary == store.location else { return }
                            storageURL = url; document = doc; photos = loadedPhotos
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

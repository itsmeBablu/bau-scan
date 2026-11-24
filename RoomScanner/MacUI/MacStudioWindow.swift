import SwiftUI

/// Native multi-window container for Studio on macOS.
struct MacStudioWindow: View {
    let designID: UUID
    @Environment(RoomStore.self) private var store
    @State private var document: SceneEditDocument?
    @State private var storageURL: URL?
    @State private var photos: [SurveyPhotoImage] = []
    @State private var error: String?
    @State private var loading = true

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
        .task(id: designID) {
            await load()
        }
    }

    private func load() async {
        loading = true
        let roots = [
            store.location.documentsURL,
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        ]
        for root in roots {
            let dir = root.appendingPathComponent("SceneEdits", isDirectory: true)
            for source in [SceneEditDocument.Source.house, .room, .technical] {
                let url = dir.appendingPathComponent("\(source.rawValue)-\(designID.uuidString).json")
                if FileManager.default.fileExists(atPath: url.path) {
                    do {
                        if let doc = try SceneEditStore.read(url, source: source, id: designID) {
                            storageURL = url
                            document = doc
                            photos = (try? await Task.detached {
                                if source == .technical {
                                    let techURL = root.appendingPathComponent("TechnicalRooms").appendingPathComponent(designID.uuidString).appendingPathExtension("technicalroom")
                                    return SurveyPhotoStore.images(technical: try TechnicalRoomPackage.read(from: techURL), studio: true)
                                }
                                let loc = StorageLocation(kind: .local, documentsURL: root)
                                let pkg = source == .house
                                    ? loc.housesURL.appendingPathComponent(designID.uuidString).appendingPathExtension(FileLayout.housePackageExtension)
                                    : loc.roomsURL.appendingPathComponent(designID.uuidString).appendingPathExtension(FileLayout.packageExtension)
                                return try SurveyPhotoStore.images(from: pkg, house: doc.shell)
                            }.value) ?? []
                            loading = false
                            return
                        }
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            }
        }
        if document == nil && error == nil {
            error = "Design not found."
        }
        loading = false
    }
}

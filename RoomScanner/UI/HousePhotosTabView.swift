import SwiftUI
import ImageIO

/// Tab content for displaying survey photos in a House or Room detail view.
struct HousePhotosTabView: View {
    let house: House
    let packageURL: URL
    @State private var photos: [ProjectPhotoAsset] = []
    @State private var selectedPhoto: ProjectPhotoAsset?
    @State private var loading = true
    @State private var error: String?
    @State private var retry = 0

    var body: some View {
        Group {
            if loading {
                ProgressView()
            } else if let error {
                ContentUnavailableView {
                    Label("Photo unavailable",systemImage:"photo.badge.exclamationmark")
                } description: { Text(error) } actions: { Button("Retry") { retry += 1 } }
            } else if photos.isEmpty {
                ContentUnavailableView("detail.photos.empty", systemImage: "camera")
            } else {
                ScrollView {
                    PhotoAlbumBrowser(assets:photos,summaries:Dictionary(uniqueKeysWithValues:Set(photos.map(\.reference.id)).map { ($0,ProjectScanSummary(house:house)) })).padding()
                }
            }
        }
        .task(id: packageURL.absoluteString+"|"+String(retry)) {
            loading = true; error = nil; photos = []; selectedPhoto = nil
            let root = packageURL, house = house
            do {
                let loaded = try await BackgroundWork.run {
                    guard let id = UUID(uuidString: root.deletingPathExtension().lastPathComponent) else { throw CocoaError(.fileReadCorruptFile) }
                    let reference = ScanVoiceNoteLibrary.reference(itemID:id,kind:root.pathExtension == "housescan" ? .house : .room,
                                                                  storageRoot:root.deletingLastPathComponent().deletingLastPathComponent())
                    return try ProjectPhotoAsset.list(from: root, house: house, reference: reference)
                }
                guard !Task.isCancelled else { return }
                photos = loaded
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                photos = []
            }
            loading = false
        }
        .sheet(item: $selectedPhoto) { photo in
            ProjectPhotoGallery(assets: photos, initial: photo.id)
        }
    }
}

/// Lightweight thumbnail renderer for survey photo data.
struct SurveyPhotoThumbnailView: View {
    let data: Data
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProgressView()
            }
        }
        .task(id: data) {
            image = nil
            let decoded = try? await PhotoThumbnailCache.shared.image(data: data)
            guard !Task.isCancelled else { return }; image = decoded
        }
        .onDisappear { image = nil }
    }
}

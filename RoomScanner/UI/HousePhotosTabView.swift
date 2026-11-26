import SwiftUI
import ImageIO

/// Tab content for displaying survey photos in a House or Room detail view.
struct HousePhotosTabView: View {
    let house: House
    let packageURL: URL
    @State private var photos: [SurveyPhotoImage] = []
    @State private var selectedPhoto: SurveyPhotoImage?
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        Group {
            if loading {
                ProgressView()
            } else if photos.isEmpty {
                ContentUnavailableView("detail.photos.empty", systemImage: "camera")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 16)], spacing: 16) {
                        ForEach(photos) { photo in
                            Button { selectedPhoto = photo } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    SurveyPhotoThumbnailView(data: photo.jpegData)
                                        .frame(height: 140)
                                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.small))
                                    Text(photo.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .task(id: packageURL) {
            loading = true
            do {
                photos = try await Task.detached { try SurveyPhotoStore.images(from: packageURL, house: house) }.value
            } catch {
                self.error = error.localizedDescription
                photos = []
            }
            loading = false
        }
        .sheet(item: $selectedPhoto) { photo in
            SurveyPhotoGallery(photos: photos, initial: photo.id)
        }
    }
}

/// Lightweight thumbnail renderer for survey photo data.
struct SurveyPhotoThumbnailView: View {
    let data: Data
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProgressView()
            }
        }
        .task(id: data) {
            if let src = CGImageSourceCreateWithData(data as CFData, nil) {
                image = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 400
                ] as CFDictionary)
            }
        }
    }
}

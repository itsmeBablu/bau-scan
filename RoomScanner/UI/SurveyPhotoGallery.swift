import SwiftUI
import ImageIO

struct SurveyPhotoGallery: View {
    let photos: [SurveyPhotoImage]
    let initial: UUID
    var flyTo: ((SurveyPhotoImage) -> Void)?
    @State private var selected: UUID?
    @State private var fullScreen = false
    @Environment(\.dismiss) private var dismiss
    private var current: SurveyPhotoImage? { photos.first { $0.id == (selected ?? initial) } }

    private func selectPrevious() {
        guard let curr = selected ?? Optional(initial),
              let idx = photos.firstIndex(where: { $0.id == curr }),
              idx > 0 else { return }
        selected = photos[idx - 1].id
    }

    private func selectNext() {
        guard let curr = selected ?? Optional(initial),
              let idx = photos.firstIndex(where: { $0.id == curr }),
              idx + 1 < photos.count else { return }
        selected = photos[idx + 1].id
    }

    var body: some View {
        NavigationStack {
            VStack(spacing:10) {
                TabView(selection:$selected) {
                    ForEach(photos) { photo in
                        SurveyPhotoCanvas(data:photo.jpegData).tag(Optional(photo.id))
                    }
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode:.automatic))
                #endif
                Text("Taken at this camera position (scan coordinates, not GPS). Device validation pending.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                HStack {
                    Button { selectPrevious() } label: { Label("Previous", systemImage: "chevron.left") }
                        .disabled(photos.firstIndex(where: { $0.id == (selected ?? initial) }) == 0)
                    Button("Full screen",systemImage:"arrow.up.left.and.arrow.down.right") { fullScreen = true }
                    if let flyTo,let current {
                        Button("Go to camera",systemImage:"viewfinder") { flyTo(current); dismiss() }
                    }
                    Button { selectNext() } label: { Label("Next", systemImage: "chevron.right") }
                        .disabled(photos.firstIndex(where: { $0.id == (selected ?? initial) }) == photos.count - 1)
                }.buttonStyle(.bordered).padding(.bottom,10)
            }
            .navigationTitle(current?.title ?? "Survey photos")
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
            #if os(macOS)
            .background {
                Group {
                    Button("") { selectPrevious() }.keyboardShortcut(.leftArrow, modifiers: [])
                    Button("") { selectNext() }.keyboardShortcut(.rightArrow, modifiers: [])
                }
                .opacity(0)
                .allowsHitTesting(false)
            }
            #endif
        }
        .onAppear { selected = initial }
        .studioPresentation(isPresented:$fullScreen) {
            NavigationStack {
                Group {
                    if let current { SurveyPhotoCanvas(data:current.jpegData).navigationTitle(current.title) }
                }.toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { fullScreen = false } } }
            }
        }
        #if os(iOS)
        .presentationDetents([.fraction(0.5),.large])
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth:600,minHeight:480)
        #endif
    }
}

struct SurveyPhotoCanvas: View {
    let data: Data
    @State private var image: CGImage?
    @State private var zoom = 1.0
    var body: some View {
        VStack {
            GeometryReader { geometry in
                ScrollView([.horizontal,.vertical]) {
                    if let image {
                        Image(decorative:image,scale:1).resizable().scaledToFit()
                            .frame(width:geometry.size.width*zoom)
                    } else { ProgressView("Loading photo…") }
                }
            }
            HStack {
                Button("Zoom out",systemImage:"minus.magnifyingglass") { zoom = max(1,zoom/1.5) }.disabled(zoom <= 1)
                Button("Zoom in",systemImage:"plus.magnifyingglass") { zoom = min(6,zoom*1.5) }.disabled(zoom >= 6)
            }.buttonStyle(.bordered).labelStyle(.iconOnly)
        }
        .task {
            guard let source = CGImageSourceCreateWithData(data as CFData,nil) else { return }
            image = CGImageSourceCreateThumbnailAtIndex(source,0,[
                kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceCreateThumbnailWithTransform:true,
                kCGImageSourceThumbnailMaxPixelSize:2048] as CFDictionary)
        }
    }
}

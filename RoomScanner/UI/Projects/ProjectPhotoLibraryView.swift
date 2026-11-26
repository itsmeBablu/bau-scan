import SwiftUI
import ImageIO

private actor ProjectPhotoThumbnailCache {
    static let shared = ProjectPhotoThumbnailCache()
    private let cache = NSCache<NSString,CGImage>()
    init() { cache.countLimit = 48; cache.totalCostLimit = 12*1_048_576 }
    func image(_ asset:ProjectPhotoAsset) throws -> CGImage {
        let info = try asset.url.resourceValues(forKeys:[.contentModificationDateKey,.fileSizeKey])
        let key = (asset.url.path+"|"+String(describing:info.contentModificationDate)+"|"+String(describing:info.fileSize)) as NSString
        if let image = cache.object(forKey:key) { return image }
        let bytes = try asset.image().jpegData
        guard let source = CGImageSourceCreateWithData(bytes as CFData,nil),let image = CGImageSourceCreateThumbnailAtIndex(source,0,[
            kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,
            kCGImageSourceThumbnailMaxPixelSize:400] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        cache.setObject(image,forKey:key,cost:image.bytesPerRow*image.height)
        return image
    }
}

struct ProjectPhotoThumbnail: View {
    let asset:ProjectPhotoAsset
    @State private var image:CGImage?
    @State private var failed = false
    var body:some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image { Image(decorative:image,scale:1).resizable().scaledToFill() }
            else if failed { Image(systemName:"photo.badge.exclamationmark") }
            else { ProgressView() }
        }.clipped().task(id:asset.id) {
            do {
                let decoded = try await ProjectPhotoThumbnailCache.shared.image(asset)
                guard !Task.isCancelled else { return }; image = decoded; failed = false
            } catch { if !Task.isCancelled { failed = true } }
        }.onDisappear { image = nil }
    }
}

struct ProjectPhotosView: View {
    let projectID:UUID
    @Environment(RenovationWorkspace.self) private var workspace
    @State private var assets:[ProjectPhotoAsset] = []
    @State private var selected:ProjectPhotoAsset?
    @State private var referenceID = ""
    @State private var query = ""
    @State private var warning:String?
    @State private var loading = false
    private var entries:[ProjectLibraryEntry] { workspace.project(projectID)?.references.compactMap(workspace.entry).filter { !$0.isDesign } ?? [] }
    private var filtered:[ProjectPhotoAsset] {
        assets.filter { (referenceID.isEmpty || $0.reference.id == referenceID) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
    }
    var body:some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:DS.Spacing.l) {
                Picker("Associated scan",selection:$referenceID) {
                    Text("All").tag("")
                    ForEach(entries) { Text(workspace.title($0)).tag($0.id) }
                }.pickerStyle(.menu)
                if loading { ProgressView("Loading photos…") }
                if filtered.isEmpty && !loading { ContentUnavailableView("No project photos yet",systemImage:"photo.on.rectangle") }
                LazyVGrid(columns:[GridItem(.adaptive(minimum:140))],spacing:DS.Spacing.l) {
                    ForEach(filtered) { asset in
                        Button { selected = asset } label: {
                            VStack(alignment:.leading,spacing:DS.Spacing.s) {
                                ProjectPhotoThumbnail(asset:asset).frame(height:DS.Size.thumbnail).clipShape(RoundedRectangle(cornerRadius:DS.Radius.thumbnail))
                                Text(asset.title).font(.subheadline).lineLimit(2)
                            }
                        }.buttonStyle(.plain)
                    }
                }
                if let warning { Text(warning).font(.caption).foregroundStyle(.secondary) }
            }.padding(DS.Spacing.l)
        }.navigationTitle("Photos").searchable(text:$query,prompt:"Search photos")
            .task(id:projectID.uuidString+workspace.notesRoot.path+String(workspace.catalogueRevision)) {
                loading = true
                let entries = entries,summaries = workspace.scanSummaries
                let result = await Task.detached(priority:.utility) { () -> ([ProjectPhotoAsset],[String]) in
                    var assets:[ProjectPhotoAsset] = [],warnings:[String] = [],ids = Set<UUID>()
                    for entry in entries {
                        if Task.isCancelled { break }
                        do {
                            for asset in try ProjectPhotoAsset.list(entry:entry,summary:summaries[entry.id]) where ids.insert(asset.photo.id).inserted {
                                guard assets.count < 10_000 else { throw CocoaError(.fileReadTooLarge) }
                                assets.append(asset)
                            }
                        } catch { warnings.append(entry.title+": "+error.localizedDescription) }
                    }
                    return (assets,warnings)
                }.value
                guard !Task.isCancelled else { return }
                assets = result.0; warning = result.1.isEmpty ? nil : result.1.joined(separator:"\n"); loading = false
            }
            .sheet(item:$selected) { asset in ProjectPhotoGallery(assets:filtered,initial:asset.id) }
    }
}

struct ProjectPhotoGallery: View {
    let assets:[ProjectPhotoAsset]
    let initial:String
    @State private var selected = ""
    @State private var fullScreen = false
    @Environment(\.dismiss) private var dismiss
    private var index:Int { assets.firstIndex { $0.id == selected } ?? 0 }
    private var current:ProjectPhotoAsset? { assets.indices.contains(index) ? assets[index] : nil }
    var body:some View {
        NavigationStack {
            TabView(selection:$selected) {
                ForEach(Array(assets.enumerated()),id:\.element.id) { offset,asset in
                    Group {
                        if abs(offset-index) <= 1 { ProjectPhotoPage(asset:asset) }
                        else { Color.clear }
                    }.tag(asset.id)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode:.automatic))
            #endif
            .navigationTitle(current?.title ?? AppLanguage.text("Photos"))
            .toolbar {
                ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup {
                    Button("Previous",systemImage:"chevron.left") { selected = assets[index-1].id }.disabled(index <= 0)
                    Button("Next",systemImage:"chevron.right") { selected = assets[index+1].id }.disabled(index+1 >= assets.count)
                    if let current { ShareLink(item:current.url) { Label("Share",systemImage:"square.and.arrow.up") } }
                    Button("Full screen",systemImage:"arrow.up.left.and.arrow.down.right") { fullScreen = true }
                }
            }
        }.onAppear { selected = initial }
            .studioPresentation(isPresented:$fullScreen) {
                NavigationStack {
                    if let current { ProjectPhotoPage(asset:current).navigationTitle(current.title)
                        .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { fullScreen = false } } } }
                }
            }
    }
}

private struct ProjectPhotoPage: View {
    let asset:ProjectPhotoAsset
    @State private var bytes:Data?
    @State private var error:String?
    var body:some View {
        Group {
            if let bytes { SurveyPhotoCanvas(data:bytes) }
            else if let error { ContentUnavailableView("Photo unavailable",systemImage:"photo.badge.exclamationmark",description:Text(error)) }
            else { ProgressView("Loading photo…") }
        }.task(id:asset.id) {
            do {
                let data = try await Task.detached(priority:.userInitiated) { try asset.image().jpegData }.value
                guard !Task.isCancelled else { return }; bytes = data
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }.onDisappear { bytes = nil }
    }
}

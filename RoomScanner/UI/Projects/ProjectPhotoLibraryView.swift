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
    @Environment(\.locale) private var locale
    @State private var assets:[ProjectPhotoAsset] = []
    @State private var selected:ProjectPhotoAsset?
    @State private var referenceID = ""
    @State private var query = ""
    @State private var warning:String?
    @State private var loading = false
    @State private var selecting = false
    @State private var selection = Set<String>()
    @State private var exporting = false
    @State private var exportURL:URL?
    @State private var exportError:String?
    @State private var exportRequest = UUID()
    @State private var exportTask:Task<Void,Never>?
    private struct NameKey:Hashable { let name:String? }
    private struct RoomKey:Hashable { let reference:String; let room:UUID? }
    @State private var building:NameKey?
    @State private var level:ProjectScanGrouping.LevelKey?
    @State private var zone:NameKey?
    @State private var room:RoomKey?
    private var entries:[ProjectLibraryEntry] { workspace.project(projectID)?.references.compactMap(workspace.entry).map { workspace.localizedEntry($0,locale:locale) }.filter { !$0.isDesign } ?? [] }
    private var filtered:[ProjectPhotoAsset] {
        assets.filter { asset in
            (referenceID.isEmpty || asset.reference.id == referenceID) &&
            (building == nil || NameKey(name:workspace.organization(for:asset.reference)?.buildingName) == building) &&
            (level == nil || levelKey(asset) == level) &&
            (zone == nil || NameKey(name:workspace.organization(for:asset.reference)?.zoneName) == zone) &&
            (room == nil || RoomKey(reference:asset.reference.id,room:asset.photo.roomID) == room) &&
            (query.isEmpty || asset.title.localizedCaseInsensitiveContains(query))
        }
    }
    private var scoped:[ProjectPhotoAsset] { assets.filter { referenceID.isEmpty || $0.reference.id == referenceID } }
    private var buildingAssets:[ProjectPhotoAsset] { scoped.filter { building == nil || NameKey(name:workspace.organization(for:$0.reference)?.buildingName) == building } }
    private var levelAssets:[ProjectPhotoAsset] { buildingAssets.filter { level == nil || levelKey($0) == level } }
    private var zoneAssets:[ProjectPhotoAsset] { levelAssets.filter { zone == nil || NameKey(name:workspace.organization(for:$0.reference)?.zoneName) == zone } }
    private var roomOptions:[ProjectPhotoAsset] {
        let groups = Dictionary(grouping:zoneAssets) { RoomKey(reference:$0.reference.id,room:$0.photo.roomID) }
        return groups.values.compactMap(\.first).sorted {
            let order = $0.roomName.localizedStandardCompare($1.roomName)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
    private func names(_ values:[String?]) -> [NameKey] {
        Array(Set(values.map { NameKey(name:$0) })).sorted {
            switch ($0.name,$1.name) {
            case let (a?,b?): return a.localizedStandardCompare(b) == .orderedAscending
            case (_?,nil): return true
            default: return false
            }
        }
    }
    private func levelKey(_ asset:ProjectPhotoAsset) -> ProjectScanGrouping.LevelKey {
        let value = workspace.organization(for:asset.reference)
        if let summary = workspace.scanSummaries[asset.reference.id],summary.stories > 1 {
            let story = summary.roomDetails.first { $0.id == asset.photo.roomID }?.story
            return .init(number:story.flatMap { value?.storyLevels?[$0] },otherName:nil)
        }
        return .init(number:value?.level,otherName:value?.otherLevelName)
    }
    private func levelTitle(_ key:ProjectScanGrouping.LevelKey) -> String {
        key.number.map { StoryNaming.localizedName(for:$0,locale:locale) } ?? key.otherName ?? AppLanguage.text("Unassigned level",locale:locale)
    }
    var body:some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:DS.Spacing.l) {
                Picker("Associated scan",selection:$referenceID) {
                    Text("All").tag("")
                    ForEach(entries) { Text(workspace.title($0,locale:locale)).tag($0.id) }
                }.pickerStyle(.menu)
                DisclosureGroup("Filters") {
                    Picker("Building",selection:$building) {
                        Text("All").tag(NameKey?.none)
                        ForEach(names(scoped.map { workspace.organization(for:$0.reference)?.buildingName }),id:\.self) { key in
                            Text(key.name ?? AppLanguage.text("Unassigned building",locale:locale)).tag(Optional(key))
                        }
                    }
                    Picker("Level",selection:$level) {
                        Text("All").tag(ProjectScanGrouping.LevelKey?.none)
                        ForEach(ProjectScanGrouping.orderedLevels(Array(Set(buildingAssets.map(levelKey))),locale:locale),id:\.self) { key in
                            Text(levelTitle(key)).tag(Optional(key))
                        }
                    }
                    Picker("Zone",selection:$zone) {
                        Text("All").tag(NameKey?.none)
                        ForEach(names(levelAssets.map { workspace.organization(for:$0.reference)?.zoneName }),id:\.self) { key in
                            Text(key.name ?? AppLanguage.text("Unassigned zone",locale:locale)).tag(Optional(key))
                        }
                    }
                    Picker("Room",selection:$room) {
                        Text("All").tag(RoomKey?.none)
                        ForEach(roomOptions) { asset in
                            Text(asset.roomName+" · "+(workspace.entry(asset.reference).map { workspace.title($0,locale:locale) } ?? asset.reference.itemID.uuidString))
                                .tag(Optional(RoomKey(reference:asset.reference.id,room:asset.photo.roomID)))
                        }
                    }
                    Button("Reset filters") { referenceID = ""; building = nil; level = nil; zone = nil; room = nil; query = "" }
                }
                if loading { ProgressView("Loading photos…") }
                if selecting {
                    HStack {
                        Text("\(selection.count) selected").font(.subheadline)
                        Spacer()
                        Button("Select visible photos") { selection.formUnion(filtered.map(\.id)) }.disabled(exporting)
                        Button("Clear") { selection = [] }.disabled(exporting)
                    }
                    Button("Export selected photos ZIP",systemImage:"archivebox") { exportSelection() }
                        .disabled(exporting || selection.isEmpty || selection.count > 1000)
                    if selection.count > 1000 { Text("Select at most 1,000 photos per ZIP.").font(.caption).foregroundStyle(.secondary) }
                }
                if exporting { ProgressView("Exporting photos…") }
                if let exportURL { ShareLink(item:exportURL) { Label("Share selected photos ZIP",systemImage:"square.and.arrow.up") } }
                if filtered.isEmpty && !loading { ContentUnavailableView("No project photos yet",systemImage:"photo.on.rectangle") }
                LazyVGrid(columns:[GridItem(.adaptive(minimum:140))],spacing:DS.Spacing.l) {
                    ForEach(filtered) { asset in
                        Button {
                            if selecting {
                                if selection.contains(asset.id) { selection.remove(asset.id) } else { selection.insert(asset.id) }
                            } else { selected = asset }
                        } label: {
                            VStack(alignment:.leading,spacing:DS.Spacing.s) {
                                ProjectPhotoThumbnail(asset:asset).frame(height:DS.Size.thumbnail).clipShape(RoundedRectangle(cornerRadius:DS.Radius.thumbnail))
                                Text(asset.title).font(.subheadline).lineLimit(2)
                            }
                        }.buttonStyle(.plain).disabled(exporting)
                            .overlay(alignment:.topTrailing) {
                                if selecting {
                                    Image(systemName:selection.contains(asset.id) ? "checkmark.circle.fill" : "circle")
                                        .padding(DS.Spacing.s).dsMaterial(in:Circle()).padding(DS.Spacing.xs).allowsHitTesting(false)
                                }
                            }
                            .accessibilityAddTraits(selection.contains(asset.id) ? .isSelected : [])
                    }
                }
                if let warning { Text(warning).font(.caption).foregroundStyle(.secondary) }
            }.padding(DS.Spacing.l)
        }.navigationTitle("Photos").searchable(text:$query,prompt:"Search photos")
            .toolbar { ToolbarItem { Button(selecting ? "Done" : "Select") { selecting.toggle() }.disabled(exporting) } }
            .task(id:projectID.uuidString+workspace.notesRoot.path+String(workspace.catalogueRevision)+locale.identifier) {
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
            .onChange(of:referenceID) { _,_ in building = nil; level = nil; zone = nil; room = nil }
            .onChange(of:building) { _,_ in level = nil; zone = nil; room = nil }
            .onChange(of:level) { _,_ in zone = nil; room = nil }
            .onChange(of:zone) { _,_ in room = nil }
            .onChange(of:selection) { _,_ in exportURL = nil }
            .onChange(of:workspace.catalogueRevision) { _,_ in cancelExport() }
            .onDisappear { cancelExport() }
            .alert("Photo export",isPresented:Binding(get:{ exportError != nil },set:{ if !$0 { exportError = nil } })) {
                Button("OK") { exportError = nil }
            } message: { Text(exportError ?? "") }
    }
    private func cancelExport() { exportRequest = UUID(); exportTask?.cancel(); exportTask = nil; exporting = false }
    private func exportSelection() {
        guard !exporting,let project = workspace.project(projectID) else { return }
        let chosen = assets.filter { selection.contains($0.id) }
        guard chosen.count == selection.count,!chosen.isEmpty else { exportError = AppLanguage.text("Some selected photos are unavailable. Refresh and select again."); return }
        let request = UUID(),organization = workspace.index.scanOrganization ?? [:],summaries = workspace.scanSummaries,locale = locale
        exportRequest = request; exporting = true; exportURL = nil
        exportTask = Task {
            let worker = Task.detached(priority:.userInitiated) {
                let target = try ExportService.scratchDirectory().appendingPathComponent(ArchivePath.component(project.name)+"-Selected-Photos.zip")
                try SelectedPhotosExporter.export(project:project,assets:chosen,organization:organization,summaries:summaries,locale:locale,to:target)
                return target
            }
            do {
                let result = try await withTaskCancellationHandler(operation:{ try await worker.value },onCancel:{ worker.cancel() })
                guard !Task.isCancelled,exportRequest == request else { return }
                exportURL = result; exporting = false; exportTask = nil
            } catch {
                guard !Task.isCancelled,exportRequest == request else { return }
                exportError = error.localizedDescription; exporting = false; exportTask = nil
            }
        }
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

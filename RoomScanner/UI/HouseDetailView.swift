import SwiftUI
import ImageIO

/// House detail view: story picker, 2D Plan / 3D Viewer / Measurements tabs,
/// export (⌘E), renamable title.
/// ('All stories' overlays stories in 3D).
struct HouseDetailView: View {
    @Environment(RoomStore.self) private var store
    let record: HouseRecord
    @State private var house: House?
    @State private var loadError: String?
    @State private var tab: Tab = .plan
    @State private var storyIndex: Int?
    @State private var renaming = false
    @State private var exporting = false
    @State private var showingRadiators = false
    @State private var showingStudio = false
    @State private var radiators: [HouseRadiator] = []
    @State private var newName = ""
    @State private var roomToRename: FloorPlan?
    @State private var newRoomName = ""
    @State private var renameError: String?
    @State private var viewerState = ViewerState()

    enum Tab: Hashable { case plan, viewer, measures, photos }

    private var currentRecord: HouseRecord { store.houseRecords.first { $0.id == record.id } ?? record }

    var body: some View {
        Group {
            if let house {
                content(house)
            } else if let loadError {
                ContentUnavailableView(loadError, systemImage: "exclamationmark.triangle")
            } else {
                ProgressView()
            }
        }
        .navigationTitle(currentRecord.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { exporting = true } label: { Label("detail.export", systemImage: "square.and.arrow.up") }
                    .disabled(house == nil)
                    #if os(iOS)
                    .keyboardShortcut("e", modifiers: .command)
                    #endif
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        viewerState.mode = .threeD
                        showingStudio = true
                    } label: { Label("Open in Design",systemImage: "square.stack.3d.up") }.disabled(house == nil)
                    Button {
                        viewerState.mode = .threeD
                        showingRadiators = true
                    } label: { Label("Radiators", systemImage: "radiator") }
                    .disabled(house == nil)
                    Button { newName = currentRecord.name; renaming = true } label: { Label("detail.rename", systemImage: "pencil") }
                } label: { Label("Options", systemImage: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $exporting) {
            if let house { ExportSheet(subject: ExportSubject(record: currentRecord, house: house, packageURL: store.packageURL(for: currentRecord))).environment(store) }
        }
        .sheet(isPresented: $showingRadiators,onDismiss: { load() }) {
            if let house {
                HouseRadiatorListView(house: house, packageURL: store.packageURL(for: currentRecord))
            }
        }
        .studioPresentation(isPresented: $showingStudio) {
            if let house {
                let seed: SceneEditDocument = {
                    var value = SceneEditDocument.seed(house: house,source: .house,id: currentRecord.id,scans: (try? HousePackage.readStructure(from: store.packageURL(for: currentRecord)))?.rooms ?? [])
                    value.includeRadiators(radiators); return value
                }()
                NavigationStack { StudioProjectView(seed: seed,storageRoot: store.location.documentsURL) }
            }
        }
        .alert("detail.rename", isPresented: $renaming) {
            TextField("detail.rename.placeholder", text: $newName)
            Button("common.ok") { rename() }
            Button("common.cancel", role: .cancel) {}
        }
        .alert("Rename room",isPresented: Binding(get: { roomToRename != nil },set: { if !$0 { roomToRename = nil } })) {
            TextField("Room name",text: $newRoomName)
            Button("Save") { renameRoom() }.disabled(newRoomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newRoomName.count > 120)
            Button("Cancel",role: .cancel) { roomToRename = nil }
        }
        .alert("Unable to rename room",isPresented: Binding(get: { renameError != nil },set: { if !$0 { renameError = nil } })) { Button("OK") { renameError = nil } } message: { Text(renameError ?? "") }
        .task(id: record.id) { load() }
    }

    /// House filtered to selected story (2D plan, measurements); `nil` = all stories.
    private func shown(_ house: House) -> House {
        guard let storyIndex, let story = house.stories.first(where: { $0.index == storyIndex }) else { return house }
        return House(id: house.id, name: house.name, stories: [story])
    }

    @ViewBuilder private func content(_ house: House) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Picker("Model view", selection: $tab) {
                    Text("detail.tab.plan").tag(Tab.plan)
                    Text("detail.tab.viewer").tag(Tab.viewer)
                    Text("detail.tab.measures").tag(Tab.measures)
                    Text("detail.tab.photos").tag(Tab.photos)
                }
                .pickerStyle(.segmented)
                if house.stories.count > 1 {
                    HStack {
                        Text("house.story").font(.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Picker("house.story", selection: $storyIndex) {
                            Text("house.story.all").tag(Int?.none)
                            ForEach(house.stories, id: \.index) { story in
                                Text(StoryNaming.localizedName(for: story.index)).tag(Int?.some(story.index))
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("house.storyPicker")
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            switch tab {
            case .plan:
                #if os(macOS)
                Plan2DView(house: shown(house))
                    .onDrag { DragExportProvider.provider(subject: ExportSubject(record: currentRecord, house: shown(house), packageURL: store.packageURL(for: currentRecord)), format: .pdf) }
                    .help("mac.dragHint")
                #else
                Plan2DView(house: shown(house))
                #endif
            case .viewer:
                VStack(spacing: 0) {
                    ViewerView(house: shown(house), state: viewerState, radiators: radiators,photoPackageURL:store.packageURL(for:currentRecord))
                    ViewerControls(state: viewerState, usdzURL: HousePackage.usdzURL(in: store.packageURL(for: currentRecord)))
                }
            case .measures: HouseMeasuresView(house: shown(house),onRename: { room in
                newRoomName = room.name; roomToRename = room
            })
            case .photos:
                HousePhotosTabView(house: shown(house), packageURL: store.packageURL(for: currentRecord))
            }
        }
        #if os(macOS)
        .background {
            Group {
                Button("") { tab = .plan }.keyboardShortcut("1", modifiers: .command)
                Button("") { tab = .viewer }.keyboardShortcut("2", modifiers: .command)
                Button("") { tab = .measures }.keyboardShortcut("3", modifiers: .command)
                Button("") { tab = .photos }.keyboardShortcut("4", modifiers: .command)
                Button("") { stepStory(-1) }.keyboardShortcut("[", modifiers: [])
                Button("") { stepStory(1) }.keyboardShortcut("]", modifiers: [])
                Button("") { viewerState.resetToken += 1 }.keyboardShortcut("0", modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
        #endif
    }

    private func stepStory(_ delta: Int) {
        guard let house, house.stories.count > 1 else { return }
        let sorted = house.stories.sorted { $0.index < $1.index }
        if let current = storyIndex, let idx = sorted.firstIndex(where: { $0.index == current }) {
            let nextIdx = idx + delta
            if nextIdx < 0 {
                storyIndex = nil
            } else if nextIdx < sorted.count {
                storyIndex = sorted[nextIdx].index
            }
        } else {
            if delta > 0 {
                storyIndex = sorted.first?.index
            } else {
                storyIndex = sorted.last?.index
            }
        }
    }

    private func load() {
        do {
            let h = try store.house(for: currentRecord)
            house = h
            radiators = (try? HousePackage.readRadiators(from: store.packageURL(for: currentRecord)))?.radiators ?? []
            if let storyIndex, !h.stories.contains(where: { $0.index == storyIndex }) { self.storyIndex = nil }
        } catch { loadError = error.localizedDescription }
    }

    private func renameRoom() {
        guard let room = roomToRename else { return }
        do { try store.renameRoom(in: currentRecord,roomID: room.id,to: newRoomName); roomToRename = nil; load() }
        catch { roomToRename = nil; renameError = error.localizedDescription }
    }

    private func rename() {
        do { try store.rename(currentRecord, to: newName); load() } catch { loadError = error.localizedDescription }
    }
}

/// House measurements: overall totals followed by a section per story and room.
struct HouseMeasuresView: View {
    let house: House
    var onRename: ((FloorPlan) -> Void)? = nil
    @AppStorage("measurementUnit") private var unit: MeasurementUnit = .both

    var body: some View {
        let hm = HouseMeasurements(house: house)
        List {
            // House area is the union of rooms on the same story: it is smaller
            // than the sum of rooms below because adjoining rooms share walls.
            // Explanatory note clarifies the difference between union and arithmetic sum.
            Section("measures.summary") {
                row(Text("house.area"), MeasurementFormat.squareMeters(hm.floorArea))
                row(Text("house.rooms"), "\(hm.roomCount)")
                row(Text("house.stories"), "\(hm.storyCount)")
                Text("house.area.footnote").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(house.stories, id: \.index) { story in
                Section(StoryNaming.localizedName(for: story.index)) {
                    ForEach(story.rooms) { room in
                        let m = RoomMeasurements(plan: room)
                        if let onRename {
                            Button { onRename(room) } label: {
                                HStack {
                                    VStack(alignment: .leading,spacing: 4) {
                                        Text(room.name).foregroundStyle(.primary)
                                        Text("\(MeasurementFormat.squareMeters(m.floorArea)) · \(MeasurementFormat.length(m.perimeter, unit: unit))").font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer(); Image(systemName: "pencil").foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain).accessibilityLabel("Rename room: "+room.name)
                        } else {
                            row(Text(room.name), "\(MeasurementFormat.squareMeters(m.floorArea)) · \(MeasurementFormat.length(m.perimeter, unit: unit))")
                        }
                    }
                }
            }
        }
    }

    private func row(_ title: Text, _ value: String) -> some View {
        HStack { title; Spacer(); Text(value).foregroundStyle(.secondary).monospacedDigit() }
    }
}

/// House library row: first story thumbnail, rooms count, stories count, area.
struct HouseRow: View {
    @Environment(RoomStore.self) private var store
    let record: HouseRecord
    @State private var thumbnail: CGImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "house").font(.title2).foregroundStyle(.tint)
                }
            }
            .frame(width: 64, height: 64)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .task(id: record.id) { thumbnail = await loadThumbnail() }
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name).font(.headline)
                Text("house.row \(record.roomCount) \(record.storyCount) \(MeasurementFormat.squareMeters(record.areaM2))")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.padding(.vertical,6)
    }

    private func loadThumbnail() async -> CGImage? {
        let url = store.packageURL(for: record)
        if let f = HousePackage.thumbnailURL(in: url), let src = CGImageSourceCreateWithURL(f as CFURL, nil),
           let img = CGImageSourceCreateImageAtIndex(src, 0, nil) { return img }
        guard let house = try? store.house(for: record), let png = PlanRenderer.thumbnailPNG(for: house) else { return nil }
        try? HousePackage.writeThumbnail(png, in: url)
        guard let src = CGImageSourceCreateWithData(png as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}

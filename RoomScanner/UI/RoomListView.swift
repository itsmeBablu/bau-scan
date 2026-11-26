import SwiftUI
import ImageIO

/// Library: houses (v2), rooms, scanning (iOS), deletion, settings.
struct RoomListView: View {
    @Binding var pendingItem: LibraryItem?

    @State private var search = ""
    var includeTechnicalRooms = true
    init(pendingItem: Binding<LibraryItem?> = .constant(nil),includeTechnicalRooms: Bool = true) {
        _pendingItem = pendingItem; self.includeTechnicalRooms = includeTechnicalRooms
    }
    @Environment(RoomStore.self) private var store
    @State private var scanMode: ScanMode?
    @State private var studioDocument: SceneEditDocument?
    @State private var showTechnicalLibrary = false
    @State private var savedTechnicalID: UUID?
    @State private var technicalRooms = TechnicalRoomLibraryStore()
    @State private var pendingDeletion: [LibraryItem] = []
    @State private var itemToRename: LibraryItem?
    @State private var proposedName = ""
    @State private var actionError: String?
    @State private var path: [LibraryItem] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.records.isEmpty && store.houseRecords.isEmpty && store.libraryProblems.isEmpty && (!includeTechnicalRooms || technicalRooms.records.isEmpty) {
                    emptyState
                } else {
                    List {
                        LibraryProblemRows()
                        if includeTechnicalRooms && !technicalRooms.records.isEmpty {
                            Section("Technical Rooms") {
                                ForEach(technicalRooms.records.filter { matches($0.name) }) { record in
                                    Button { savedTechnicalID = record.id; showTechnicalLibrary = true } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "cube.transparent").font(.title2).foregroundStyle(.tint).frame(width: 64,height: 64).background(.quaternary,in: RoundedRectangle(cornerRadius: DS.Radius.thumbnail))
                                            VStack(alignment: .leading) {
                                                Text(record.name).font(.headline)
                                                Text("Open saved 3D scan").font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                        }.contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        if !store.houseRecords.isEmpty {
                            Section("library.houses") {
                                ForEach(store.houseRecords.filter { matches($0.name) }) { record in
                                    HStack {
                                        NavigationLink(value: LibraryItem.house(record)) { HouseRow(record: record) }
                                        Menu { itemMenu(for: .house(record)) } label: { Image(systemName: "ellipsis").frame(minWidth: 44,minHeight: 44).foregroundStyle(.secondary) }
                                            .accessibilityLabel("Options for \(record.name)")
                                    }
                                        .contextMenu { itemMenu(for: .house(record)) }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) { itemActions(for: .house(record)) }
                                }
                                .onDelete { offsets in let filtered = store.houseRecords.filter { matches($0.name) }; pendingDeletion = offsets.map { .house(filtered[$0]) } }
                            }
                        }
                        Section(store.houseRecords.isEmpty ? "" : "library.rooms") {
                            ForEach(store.records.filter { matches($0.name) }) { record in
                                HStack {
                                    NavigationLink(value: LibraryItem.room(record)) { RoomRow(record: record) }
                                    Menu { itemMenu(for: .room(record)) } label: { Image(systemName: "ellipsis").frame(minWidth: 44,minHeight: 44).foregroundStyle(.secondary) }
                                        .accessibilityLabel("Options for \(record.name)")
                                }
                                        .contextMenu { itemMenu(for: .room(record)) }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) { itemActions(for: .room(record)) }
                            }
                            .onDelete { offsets in let filtered = store.records.filter { matches($0.name) }; pendingDeletion = offsets.map { .room(filtered[$0]) } }
                        }
                    }.listStyle(.plain)
                    .overlay {
                        if !search.isEmpty && !store.records.contains(where: { matches($0.name) }) && !store.houseRecords.contains(where: { matches($0.name) }) && (!includeTechnicalRooms || !technicalRooms.records.contains(where: { matches($0.name) })) {
                            ContentUnavailableView.search(text: search)
                        }
                    }
                }
            }
            #if os(iOS)
            .navigationTitle(includeTechnicalRooms ? "Library" : "House")
            .searchable(text: $search,prompt: includeTechnicalRooms ? "Houses, rooms and technical surveys" : "Search houses and rooms")
            #else
            .navigationTitle(Text("app.name"))
            #endif
            .navigationDestination(for: LibraryItem.self) { item in
                switch item {
                case .room(let record): RoomDetailView(record: record)
                case .house(let record): HouseDetailView(record: record)
                }
            }
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { scanMode = .room } label: { Label("list.scanRoom", systemImage: "square.split.bottomrightquarter") }
                        Button { scanMode = .house } label: { Label("list.scanHouse", systemImage: "house") }
                        if includeTechnicalRooms {
                            Button { scanMode = .technicalRoom } label: { Label("Scan Technik Room", systemImage: "wrench.and.screwdriver") }
                        }
                    } label: { Label("New scan", systemImage: "plus") }
                    .disabled(!scanSupported)
                }
                #endif
            }
            #if os(iOS)
            .fullScreenCover(item: $scanMode, onDismiss: {
                reloadTechnicalRooms()
                if savedTechnicalID != nil { showTechnicalLibrary = true }
            }) { mode in
                if mode == .technicalRoom {
                    TechnicalRoomScanView(onSaved: { savedTechnicalID = $0 })
                } else {
                    ScanView(mode: mode, onSaved: { path = [$0] }).environment(store)
                }
            }
            #endif
        }
        .studioPresentation(item: $studioDocument) { document in
            NavigationStack { StudioProjectView(seed: document,storageRoot: store.location.documentsURL) }
        }
        .sheet(isPresented: $showTechnicalLibrary, onDismiss: { savedTechnicalID = nil; reloadTechnicalRooms() }) { TechnicalRoomLibraryView(initialSelection: savedTechnicalID) }
        .confirmationDialog("list.delete.confirm \(pendingDeletion.first?.name ?? "")", isPresented: Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } }), titleVisibility: .visible) {
            Button("common.delete", role: .destructive) { confirmDeletion() }
        } message: { Text("list.delete.message") }
        .alert("Rename", isPresented: Binding(get: { itemToRename != nil }, set: { if !$0 { itemToRename = nil } }), presenting: itemToRename) { _ in
            TextField("Name", text: $proposedName)
            Button("Save") { renameItem() }
                .disabled(proposedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { itemToRename = nil }
        }
        .alert("Unable to complete action", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK") { actionError = nil }
        } message: { Text(actionError ?? "") }
        .onChange(of: pendingItem) { _,item in
            if let item { store.reload(); path = [item]; pendingItem = nil }
        }
        .onAppear {
            store.reload()
            reloadTechnicalRooms()
            // `-RoomScannerAutoOpenFirst YES`: opens first room automatically (screenshots, testing).
            if UserDefaults.standard.bool(forKey: "RoomScannerAutoOpenFirst") {
                if let first = store.houseRecords.first { path = [.house(first)] } else if let first = store.records.first { path = [.room(first)] }
            }
        }
    }

    private func matches(_ name: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || name.localizedCaseInsensitiveContains(query)
    }
    private func reloadTechnicalRooms() {
        do { try technicalRooms.reload() } catch { actionError = error.localizedDescription }
    }

    private var scanSupported: Bool {
        #if canImport(RoomPlan)
        return ScanCoordinator.isSupported
        #else
        return false
        #endif
    }

    @ViewBuilder private var emptyState: some View {
        #if os(iOS)
        if scanSupported {
            ContentUnavailableView {
                VStack(spacing: 16) {
                    Image(systemName: "square.stack").dsIcon(.large,weight:.light).foregroundStyle(.secondary)
                    Text("list.empty.title").font(.title2.bold())
                }
            } description: {
                Text("list.empty.message")
            } actions: {
                Button { scanMode = .room } label: { Label("list.scanRoom", systemImage: "camera.viewfinder") }
                    .dsProminentControl()

                Button { scanMode = .house } label: { Label("list.scanHouse", systemImage: "house") }
                    .buttonStyle(.bordered)
                if includeTechnicalRooms {
                    Button { scanMode = .technicalRoom } label: { Label("Scan Technik Room", systemImage: "wrench.and.screwdriver") }
                        .buttonStyle(.bordered)
                }
            }
        } else {
            UnsupportedDeviceView()
        }
        #else
        ContentUnavailableView {
            VStack(spacing: 14) {
                BrandLogoView(size: 64)
                Text("list.empty.title").font(.title2.bold())
            }
        } description: {
            Text("list.empty.mac")
        }
        #endif
    }

    private func confirmDeletion() {
        for item in pendingDeletion {
            do { try store.delete(item) } catch { actionError = error.localizedDescription }
        }
        pendingDeletion = []
    }

    @ViewBuilder private func itemMenu(for item: LibraryItem) -> some View {
        Button { openStudio(item) } label: { Label("Studio",systemImage: "square.stack.3d.up") }
        Button { beginRenaming(item) } label: { Label("Rename", systemImage: "pencil") }
        Button(role: .destructive) { pendingDeletion = [item] } label: { Label("Delete", systemImage: "trash") }
    }
    private func openStudio(_ item: LibraryItem) {
        do {
            switch item {
            case .house(let record):
                let url = store.packageURL(for: record)
                var document = SceneEditDocument.seed(house: try store.house(for: record),source: .house,id: record.id,scans: try HousePackage.readStructure(from: url)?.rooms ?? [])
                document.includeRadiators(try HousePackage.readRadiators(from: url)?.radiators ?? [])
                studioDocument = document
            case .room(let record):
                let scan = try RoomPackage.readScan(from: store.packageURL(for: record))
                studioDocument = .seed(house: House(room: try store.plan(for: record)),source: .room,id: record.id,scans: scan.map { [$0] } ?? [])
            }
        } catch { actionError = error.localizedDescription }
    }

    @ViewBuilder private func itemActions(for item: LibraryItem) -> some View {
        Button(role: .destructive) { pendingDeletion = [item] } label: { Label("Delete", systemImage: "trash") }
        Button { beginRenaming(item) } label: { Label("Rename", systemImage: "pencil") }
    }

    private func beginRenaming(_ item: LibraryItem) {
        proposedName = item.name
        itemToRename = item
    }

    private func renameItem() {
        guard let itemToRename else { return }
        do {
            try store.rename(itemToRename,to:proposedName)
        } catch { actionError = error.localizedDescription }
        self.itemToRename = nil
    }
}

struct RoomRow: View {
    @Environment(RoomStore.self) private var store
    let record: RoomRecord
    @State private var thumbnail: CGImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "square.split.bottomrightquarter").font(.title2).foregroundStyle(.tint)
                }
            }
            .frame(width: 64, height: 64)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumbnail, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.thumbnail, style: .continuous)
                    .stroke(.primary.opacity(0.08), lineWidth: 0.5)
            }
            .task(id: record.id) { thumbnail = await loadThumbnail() }
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name).font(.headline)
                Text("\(MeasurementFormat.squareMeters(record.areaM2)) · \(record.createdAt, format: .dateTime.day().month().year())")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.padding(.vertical,6)
    }

    /// Package thumbnail; if missing, rendered on the fly and persisted.
    private func loadThumbnail() async -> CGImage? {
        let url = store.packageURL(for: record)
        if let f = RoomPackage.thumbnailURL(in: url), let src = CGImageSourceCreateWithURL(f as CFURL, nil),
           let img = CGImageSourceCreateImageAtIndex(src, 0, nil) { return img }
        guard let plan = try? store.plan(for: record) else { return nil }
        var r = PlanRenderer(); r.options.mode = .fill
        let img = r.image(House(room: plan), pixels: CGSize(width: 600, height: 400))
        if let png = PlanRenderer.thumbnailPNG(for: plan) { try? RoomPackage.writeThumbnail(png, in: url) }
        return img
    }
}

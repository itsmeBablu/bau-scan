import SwiftUI
import ImageIO

/// Library: houses (v2), rooms, scanning (iOS), deletion, settings.
struct RoomListView: View {
    @Environment(RoomStore.self) private var store
    @State private var scanMode: ScanMode?
    @State private var showSettings = false
    @State private var showStudio = false
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
                if store.records.isEmpty && store.houseRecords.isEmpty && technicalRooms.records.isEmpty {
                    emptyState
                } else {
                    List {
                        if !technicalRooms.records.isEmpty {
                            Section("Technical Rooms") {
                                ForEach(technicalRooms.records) { record in
                                    Button { savedTechnicalID = record.id; showTechnicalLibrary = true } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "cube.transparent").font(.title2).frame(width: 42)
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
                                ForEach(store.houseRecords) { record in
                                    HStack {
                                        NavigationLink(value: LibraryItem.house(record)) { HouseRow(record: record) }
                                        Menu { itemMenu(for: .house(record)) } label: { Image(systemName: "ellipsis.circle").padding(8) }
                                            .accessibilityLabel("Options for \(record.name)")
                                    }
                                        .contextMenu { itemMenu(for: .house(record)) }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) { itemActions(for: .house(record)) }
                                }
                                .onDelete { pendingDeletion = $0.map { .house(store.houseRecords[$0]) } }
                            }
                        }
                        Section(store.houseRecords.isEmpty ? "" : "library.rooms") {
                            ForEach(store.records) { record in
                                HStack {
                                    NavigationLink(value: LibraryItem.room(record)) { RoomRow(record: record) }
                                    Menu { itemMenu(for: .room(record)) } label: { Image(systemName: "ellipsis.circle").padding(8) }
                                        .accessibilityLabel("Options for \(record.name)")
                                }
                                        .contextMenu { itemMenu(for: .room(record)) }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) { itemActions(for: .room(record)) }
                            }
                            .onDelete { pendingDeletion = $0.map { .room(store.records[$0]) } }
                        }
                    }
                }
            }
            .navigationTitle(Text("app.name"))
            .navigationDestination(for: LibraryItem.self) { item in
                switch item {
                case .room(let record): RoomDetailView(record: record)
                case .house(let record): HouseDetailView(record: record)
                }
            }
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) {
                    Button { showStudio = true } label: { Label("Studio",systemImage: "square.stack.3d.up") }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { showSettings = true } label: { Label("settings.title", systemImage: "gearshape") }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button { savedTechnicalID = nil; showTechnicalLibrary = true } label: { Label("Technical Room library", systemImage: "wrench.and.screwdriver") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { scanMode = .room } label: { Label("list.scanRoom", systemImage: "square.split.bottomrightquarter") }
                        Button { scanMode = .house } label: { Label("list.scanHouse", systemImage: "house") }
                        Button { scanMode = .technicalRoom } label: { Label("Scan Technik Room", systemImage: "wrench.and.screwdriver") }
                    } label: { Label("list.scan", systemImage: "camera.viewfinder") }
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
        .sheet(isPresented: $showSettings) { SettingsView().environment(store) }
        .sheet(isPresented: $showStudio) { StudioLibraryView().environment(store) }
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
        .onAppear {
            store.reload()
            reloadTechnicalRooms()
            // `-RoomScannerAutoOpenFirst YES`: opens first room automatically (screenshots, testing).
            if UserDefaults.standard.bool(forKey: "RoomScannerAutoOpenFirst") {
                if let first = store.houseRecords.first { path = [.house(first)] } else if let first = store.records.first { path = [.room(first)] }
            }
        }
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
                    BrandLogoView(size: 72)
                        .liquidGlass(cornerRadius: 18, tint: AppTheme.primaryYellow, hasBorder: true, shadowRadius: 8)
                    Text("list.empty.title").font(.title2.bold())
                }
            } description: {
                Text("list.empty.message")
            } actions: {
                Button { scanMode = .room } label: { Label("list.scanRoom", systemImage: "camera.viewfinder") }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primaryYellow)
                    .foregroundStyle(AppTheme.darkCharcoal)
                Button { scanMode = .house } label: { Label("list.scanHouse", systemImage: "house") }
                    .buttonStyle(.bordered)
                Button { scanMode = .technicalRoom } label: { Label("Scan Technik Room", systemImage: "wrench.and.screwdriver") }
                    .buttonStyle(.bordered)
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
        Button { beginRenaming(item) } label: { Label("Rename", systemImage: "pencil") }
        Button(role: .destructive) { pendingDeletion = [item] } label: { Label("Delete", systemImage: "trash") }
    }

    @ViewBuilder private func itemActions(for item: LibraryItem) -> some View {
        Button(role: .destructive) { pendingDeletion = [item] } label: { Label("Delete", systemImage: "trash") }
        Button { beginRenaming(item) } label: { Label("Rename", systemImage: "pencil") }.tint(.blue)
    }

    private func beginRenaming(_ item: LibraryItem) {
        proposedName = item.name
        itemToRename = item
    }

    private func renameItem() {
        guard let itemToRename else { return }
        do {
            switch itemToRename {
            case .room(let record): try store.rename(record, to: proposedName)
            case .house(let record): try store.rename(record, to: proposedName)
            }
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
                    Image(systemName: "square.split.bottomrightquarter").font(.title2).foregroundStyle(AppTheme.primaryYellow)
                }
            }
            .frame(width: 72, height: 48)
            .background(AppTheme.softBackgroundTint)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.primaryYellow.opacity(0.35), lineWidth: 1)
            }
            .task(id: record.id) { thumbnail = await loadThumbnail() }
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name).font(.headline)
                Text("\(MeasurementFormat.squareMeters(record.areaM2)) · \(record.createdAt, format: .dateTime.day().month().year())")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
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

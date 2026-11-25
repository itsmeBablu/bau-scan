import SwiftUI
import AppKit

/// Mac window: sidebar (houses, rooms, utility rooms, design studio, search, iCloud status,
/// drag export, package) and tabbed detail; executes menu actions (export, print, Finder, import).
struct MacRootView: View {
    @Environment(RoomStore.self) private var store
    @State private var technicalStore = TechnicalRoomLibraryStore()
    @State private var designs: [SceneEditDocument] = []
    @State private var designRoots: [UUID: URL] = [:]
    @State private var appState = MacAppState()
    @State private var pendingDeletion: MacItem?
    @State private var search = ""
    @State private var exportSheet: ExportRequest?
    @State private var errorMessage: String?
    @State private var showingTechnicalLibrary = false
    @State private var showingStudio = false
    @State private var technicalImport: URL?

    struct ExportRequest: Identifiable { let id = UUID(); let subject: ExportSubject; let format: ExportFormat? }
    struct OrganisedRequest: Identifiable { let id = UUID(); let subject: ExportSubject; let photosOnly: Bool }
    @State private var organisedRequest: OrganisedRequest?

    private func matches(_ name: String) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || name.localizedCaseInsensitiveContains(q)
    }

    private var filteredHouses: [HouseRecord] { store.houseRecords.filter { matches($0.name) } }
    private var filteredRooms: [RoomRecord] { store.records.filter { matches($0.name) } }
    private var filteredTechnical: [TechnicalRoomManifest] { technicalStore.records.filter { matches($0.name) } }
    private var filteredDesigns: [SceneEditDocument] { designs.filter { matches($0.title) } }

    private var isEmpty: Bool {
        store.records.isEmpty && store.houseRecords.isEmpty && store.libraryProblems.isEmpty && technicalStore.records.isEmpty && designs.isEmpty
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $appState.selected) {
                LibraryProblemRows(reveal:{ NSWorkspace.shared.activateFileViewerSelecting([$0]) })
                if !filteredHouses.isEmpty {
                    Section("library.houses") {
                        ForEach(filteredHouses) { record in
                            HouseRow(record: record).tag(MacItem.house(record))
                                .modifier(RowActions(item: .house(record), url: store.packageURL(for: record), appState: appState, pendingDeletion: $pendingDeletion))
                        }
                    }
                }
                if !filteredRooms.isEmpty {
                    Section(filteredHouses.isEmpty ? "" : "library.rooms") {
                        ForEach(filteredRooms) { record in
                            RoomRow(record: record).tag(MacItem.room(record))
                                .modifier(RowActions(item: .room(record), url: store.packageURL(for: record), appState: appState, pendingDeletion: $pendingDeletion))
                        }
                    }
                }
                if !filteredTechnical.isEmpty {
                    Section("sidebar.technicalRooms") {
                        ForEach(filteredTechnical) { manifest in
                            TechnicalRoomRow(manifest: manifest).tag(MacItem.technicalRoom(manifest))
                                .modifier(RowActions(item: .technicalRoom(manifest), url: technicalStore.url(for: manifest.id), appState: appState, pendingDeletion: $pendingDeletion))
                        }
                    }
                }
                if !filteredDesigns.isEmpty {
                    Section("sidebar.designs") {
                        ForEach(filteredDesigns, id: \.sourceID) { document in
                            DesignRow(document: document).tag(MacItem.design(designRef(document)))
                                .modifier(RowActions(item: .design(designRef(document)), url: designURL(for: document), appState: appState, pendingDeletion: $pendingDeletion))
                        }
                    }
                }
            }
            .searchable(text: $search, placement: .sidebar, prompt: Text("mac.search"))
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .toolbar {
                ToolbarItem(placement: .automatic) { CloudStatusBadge() }
            }
            .overlay {
                if isEmpty { Text("list.empty.title").foregroundStyle(.secondary).font(.callout) }
                else if !search.isEmpty && filteredHouses.isEmpty && filteredRooms.isEmpty && filteredTechnical.isEmpty && filteredDesigns.isEmpty { ContentUnavailableView.search(text:search) }
            }
        } detail: {
            switch appState.selected {
            case .house(let record) where store.houseRecords.contains(record):
                HouseDetailView(record: record).id(record.id)
            case .room(let record) where store.records.contains(record):
                RoomDetailView(record: record).id(record.id)
            case .technicalRoom(let manifest) where technicalStore.records.contains(manifest):
                TechnicalStoredRoomView(id: manifest.id, library: technicalStore).id(manifest.id)
            case .design(let reference):
                MacDesignDetail(reference:reference,root:designRoots[reference.sourceID] ?? store.location.documentsURL).id(reference.id)
            default:
                MacEmptyStateView { importPackage() }
            }
        }
        .focusedSceneValue(\.macAppState, appState)
        .confirmationDialog("list.delete.confirm \(pendingDeletion?.name ?? "")", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), titleVisibility: .visible) {
            Button("common.delete", role: .destructive) {
                if let item = pendingDeletion {
                    do {
                        let url: URL
                        switch item {
                        case .house(let h): url = store.packageURL(for:h)
                        case .room(let r): url = store.packageURL(for:r)
                        case .technicalRoom(let t): url = technicalStore.url(for:t.id)
                        case .design(let d): url = designURL(for:d)
                        }
                        try FileManager.default.trashItem(at:url,resultingItemURL:nil)
                        store.reload(); try technicalStore.reload()
                        Task { do { try await loadDesigns() } catch { errorMessage = error.localizedDescription } }
                    } catch { errorMessage = error.localizedDescription; return }
                    if appState.selected?.id == item.id { appState.selected = nil }
                }
                pendingDeletion = nil
            }
        } message: { Text("list.delete.message") }
        .navigationTitle(Text("app.name"))
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            if url.pathExtension == "technicalroom" {
                Task {
                    do {
                        let id = try await technicalStore.importPackage(url)
                        if let rec = technicalStore.records.first(where: { $0.id == id }) {
                            appState.selected = .technicalRoom(rec)
                        }
                    } catch { errorMessage = error.localizedDescription }
                }
                return true
            } else if [FileLayout.packageExtension, FileLayout.housePackageExtension].contains(url.pathExtension) {
                do {
                    let item = try store.importAny(from: url)
                    switch item {
                    case .house(let h): appState.selected = .house(h)
                    case .room(let r): appState.selected = .room(r)
                    }
                    return true
                } catch {
                    errorMessage = error.localizedDescription
                    return false
                }
            }
            return false
        }
        .task {
            await store.activateCloudIfAvailable()
            do { try technicalStore.reload(); try await loadDesigns() } catch { errorMessage = error.localizedDescription }
            autoSelect()
        }
        .task(id:store.location.documentsURL) {
            technicalStore = TechnicalRoomLibraryStore(root:store.location.documentsURL.appendingPathComponent("TechnicalRooms"))
            do { try technicalStore.reload(); try await loadDesigns(); refreshSelection() } catch { errorMessage = error.localizedDescription }
        }
        .onChange(of:technicalStore.records) { _,_ in refreshSelection() }
        .onChange(of: store.records) { _, _ in refreshSelection() }
        .onChange(of: store.houseRecords) { _, _ in refreshSelection() }
        .onChange(of: appState.selected, initial: true) { _, item in
            appState.availableFormats = item.flatMap { availableFormats(for: $0) } ?? []
        }
        .onChange(of: appState.pendingAction) { _, action in
            guard let action else { return }
            appState.pendingAction = nil
            perform(action)
        }
        .onOpenURL { url in
            if TechnicalGoogleAIAccount.handle(url) { return }
            if url.pathExtension == "technicalroom" {
                Task {
                    do {
                        let id = try await technicalStore.importPackage(url)
                        if let rec = technicalStore.records.first(where: { $0.id == id }) {
                            appState.selected = .technicalRoom(rec)
                        }
                    } catch { errorMessage = error.localizedDescription }
                }
                return
            }
            guard [FileLayout.packageExtension, FileLayout.housePackageExtension].contains(url.pathExtension) else { return }
            do {
                let item = try store.importAny(from: url)
                switch item {
                case .house(let h): appState.selected = .house(h)
                case .room(let r): appState.selected = .room(r)
                }
            } catch { errorMessage = error.localizedDescription }
        }
        .sheet(item: $exportSheet) { req in
            ExportSheet(subject: req.subject, initialFormat: req.format).environment(store)
        }
        .sheet(item: $organisedRequest) { req in
            OrganisedExportSheet(subject: req.subject, photosOnly: req.photosOnly).environment(store)
        }
        .sheet(isPresented: $showingTechnicalLibrary) { TechnicalRoomLibraryView(importURL: technicalImport) }
        .sheet(isPresented: $showingStudio) { StudioLibraryView().environment(store) }
        .alert("mac.actionFailed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("common.ok") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .frame(minWidth: 900, minHeight: 600)
    }

    private func designURL(for document: SceneEditDocument) -> URL {
        designURL(for:DesignRef(document))
    }
    private func designRef(_ document: SceneEditDocument) -> DesignRef {
        DesignRef(document,modifiedAt:(try? designURL(for:document).resourceValues(forKeys:[.contentModificationDateKey]))?.contentModificationDate)
    }
    private func designURL(for document: DesignRef) -> URL {
        let root = designRoots[document.sourceID] ?? store.location.documentsURL
        return root.appendingPathComponent("SceneEdits/\(document.source.rawValue)-\(document.sourceID.uuidString).json")
    }

    /// Context menu and package drag provider common to all row types.
    private struct RowActions: ViewModifier {
        let item: MacItem
        let url: URL
        let appState: MacAppState
        @Binding var pendingDeletion: MacItem?
        @Environment(\.openWindow) private var openWindow
        func body(content: Content) -> some View {
            content
                .onDrag { DragExportProvider.packageProvider(url: url) }
                .contextMenu {
                    switch item {
                    case .house, .room:
                        Button("mac.menu.export") { appState.selected = item; appState.request(.export(nil)) }
                        Button("mac.menu.exportOrganised") { appState.selected = item; appState.request(.exportOrganised(false)) }
                        Button("mac.menu.exportPhotosOnly") { appState.selected = item; appState.request(.exportOrganised(true)) }
                    case .design(let d):
                        Button("Open in new window") { openWindow(value: d.sourceID) }
                    default:
                        EmptyView()
                    }
                    Button("mac.menu.revealInFinder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    Divider()
                    Button("common.delete", role: .destructive) { pendingDeletion = item }
                }
        }
    }

    /// Keeps selection in sync with lists (delete, rename, recompute).
    private func refreshSelection() {
        switch appState.selected {
        case .room(let r):
            if let fresh = store.records.first(where: { $0.id == r.id }) {
                if fresh != r { appState.selected = .room(fresh) }
            } else { appState.selected = nil }
        case .house(let h):
            if let fresh = store.houseRecords.first(where: { $0.id == h.id }) {
                if fresh != h { appState.selected = .house(fresh) }
            } else { appState.selected = nil }
        case .technicalRoom(let t):
            if let fresh = technicalStore.records.first(where: { $0.id == t.id }) {
                if fresh != t { appState.selected = .technicalRoom(fresh) }
            } else { appState.selected = nil }
        case .design(let d):
            if !designs.contains(where: { $0.sourceID == d.sourceID && $0.source == d.source }) { appState.selected = nil }
        case nil: break
        }
    }

    private func availableFormats(for item: MacItem) -> [ExportFormat] {
        switch item {
        case .room(let r): ExportService.availableFormats(packageURL: store.packageURL(for: r))
        case .house(let h): ExportService.availableFormats(usdzURL: HousePackage.usdzURL(in: store.packageURL(for: h)), usdzMeshURL: nil)
        case .technicalRoom, .design: []
        }
    }

    /// Export subject for selected item (reloaded from package).
    private func subject(for item: MacItem) throws -> ExportSubject? {
        switch item {
        case .room(let r): ExportSubject(record:r,plan:try store.plan(for:r),packageURL:store.packageURL(for:r))
        case .house(let h): ExportSubject(record:h,house:try store.house(for:h),packageURL:store.packageURL(for:h))
        case .technicalRoom, .design: nil
        }
    }

    private func autoSelect() {
        store.reload()
        if UserDefaults.standard.bool(forKey: "RoomScannerAutoOpenFirst"), appState.selected == nil {
            if let h = store.houseRecords.first { appState.selected = .house(h) }
            else if let r = store.records.first { appState.selected = .room(r) }
            else if let t = technicalStore.records.first { appState.selected = .technicalRoom(t) }
            else if let d = designs.first { appState.selected = .design(designRef(d)) }
        }
    }

    private func perform(_ action: MacAppState.Action) {
        do {
        switch action {
        case .export(let format):
            guard let item = appState.selected, let subject = try subject(for: item) else { return }
            exportSheet = ExportRequest(subject: subject, format: format)
        case .exportOrganised(let photosOnly):
            guard let item = appState.selected, let subject = try subject(for: item) else { return }
            organisedRequest = OrganisedRequest(subject: subject, photosOnly: photosOnly)
        case .print:
            guard let item = appState.selected, let subject = try subject(for: item) else { return }
            try PrintController.printPlan(subject.house,title:subject.name,window:NSApp.keyWindow)
        case .revealInFinder:
            guard let item = appState.selected else { return }
            let url: URL
            switch item {
            case .house(let h): url = store.packageURL(for: h)
            case .room(let r): url = store.packageURL(for: r)
            case .technicalRoom(let t): url = technicalStore.url(for: t.id)
            case .design(let d): url = designURL(for: d)
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .openLibraryFolder:
            try store.location.prepare()
            NSWorkspace.shared.open(store.location.documentsURL)
        case .importPackage:
            importPackage()
        }
        } catch { errorMessage = error.localizedDescription }
    }

    private func importPackage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.roomScan, .houseScan, .technicalRoom]
        panel.allowsMultipleSelection = true
        panel.message = AppLanguage.text("mac.import.message")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if url.pathExtension == "technicalroom" {
                Task {
                    do {
                        let id = try await technicalStore.importPackage(url)
                        if let rec = technicalStore.records.first(where: { $0.id == id }) {
                            appState.selected = .technicalRoom(rec)
                        }
                    } catch { errorMessage = error.localizedDescription }
                }
            } else {
                do {
                    let item = try store.importAny(from: url)
                    switch item {
                    case .house(let h): appState.selected = .house(h)
                    case .room(let r): appState.selected = .room(r)
                    }
                } catch { errorMessage = error.localizedDescription }
            }
        }
    }

    private func loadDesigns() async throws {
        let primary = store.location.documentsURL
        let local = technicalStore.root.deletingLastPathComponent()
        let roots = primary.standardizedFileURL == local.standardizedFileURL ? [primary] : [primary, local]
        let loaded = try await Task.detached {
            var results: [(SceneEditDocument, URL)] = []
            for documents in roots {
                let root = documents.appendingPathComponent("SceneEdits", isDirectory: true)
                guard FileManager.default.fileExists(atPath: root.path) else { continue }
                let files = try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).filter { $0.pathExtension == "json" }.prefix(200)
                for file in files {
                    let name = file.deletingPathExtension().lastPathComponent
                    guard let separator = name.firstIndex(of: "-"),
                          let source = SceneEditDocument.Source(rawValue: String(name[..<separator])),
                          let id = UUID(uuidString: String(name[name.index(after: separator)...])) else { continue }
                    if let value = try SceneEditStore.read(file, source: source, id: id),
                       !results.contains(where: { $0.0.source == source && $0.0.sourceID == id }) {
                        results.append((value, documents))
                    }
                }
            }
            return results.sorted { $0.0.title.localizedStandardCompare($1.0.title) == .orderedAscending }
        }.value
        guard !Task.isCancelled,primary == store.location.documentsURL else { return }
        designs = loaded.map { $0.0 }
        designRoots = Dictionary(loaded.map { ($0.0.sourceID, $0.1) }, uniquingKeysWith: { first, _ in first })
    }
}

/// Technical Room row in Mac sidebar.
private struct TechnicalRoomRow: View {
    let manifest: TechnicalRoomManifest
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cube.transparent").font(.title2).foregroundStyle(.tint)
                .frame(width: 48, height: 48)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(manifest.name).font(.headline)
                Text(manifest.modifiedAt, format: .dateTime.day().month().year())
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Design row in Mac sidebar.
private struct DesignRow: View {
    let document: SceneEditDocument
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up").font(.title2).foregroundStyle(.tint)
                .frame(width: 48, height: 48)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(document.title).font(.headline)
                Text(document.source == .house ? "House" : (document.source == .technical ? "Utility room" : "Room"))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

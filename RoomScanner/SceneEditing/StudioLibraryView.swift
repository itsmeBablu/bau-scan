import SwiftUI

struct StudioLibraryView: View {
    var embedded = false
    var onSettings: (() -> Void)? = nil
    @Environment(RoomStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var mode = Mode.house
    @State private var technical: TechnicalRoomLibraryStore?
    @State private var launch: Launch?
    @State private var designs: [SceneEditDocument] = []
    @State private var designRoots: [String:URL] = [:]
    @State private var loadRequest = UUID()
    @State private var active = false
    @State private var error: String?
    @State private var busy = false
    enum Mode: String,CaseIterable { case house = "Whole home", technical = "Utility room" }
    private struct Launch: Identifiable { let id = UUID(); let document: SceneEditDocument; var root: URL? = nil }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Design type",selection: $mode) { ForEach(Mode.allCases,id: \.self) { Text(AppLanguage.text($0.rawValue)).tag($0) } }.pickerStyle(.segmented)
                    Text("Create a separate design from a saved scan. Original scans, measurements and survey evidence remain unchanged.").font(.callout).foregroundStyle(.secondary)
                }
                if !filteredDesigns.isEmpty {
                    Section("Saved designs") {
                        ForEach(filteredDesigns.map { SceneEditCatalogue.Entry(document:$0,root:designRoots[DesignRef($0).id] ?? store.location.documentsURL) }) { entry in
                            projectButton(entry.document.title,icon: "square.stack.3d.up") { launch = Launch(document:entry.document,root:entry.root) }
                        }
                    }
                }
                if mode == .house {
                    Section("Start from a House scan") {
                        ForEach(store.houseRecords.filter { !hasDesign(.house,id:$0.id,root:store.location.documentsURL) }) { record in
                            projectButton(record.name,icon: "house") { openHouse(record) }
                        }
                        if store.houseRecords.isEmpty { Text("Saved House scans will appear here.").foregroundStyle(.secondary) }
                    }
                    Section("Start from a room scan") {
                        ForEach(store.records.filter { !hasDesign(.room,id:$0.id,root:store.location.documentsURL) }) { record in
                            projectButton(record.name,icon: "square.dashed") { openRoom(record) }
                        }
                    }
                } else {
                    Section("Start from a Technik Room survey") {
                        ForEach((technical?.records ?? []).filter { !hasDesign(.technical,id:$0.id,root:technical?.root.deletingLastPathComponent() ?? store.location.documentsURL) }) { record in
                            projectButton(record.name,icon: "pipe.and.drop") { openTechnical(record.id) }
                        }
                        if technical?.records.isEmpty != false { Text("Save a Technik Room survey first. Accepted MEP suggestions and survey annotations can become editable models.").font(.callout).foregroundStyle(.secondary) }
                    }
                }
                if busy { ProgressView("Preparing design…") }
                Section {
                    Text(mode == .house ? "Recognised furniture is replaced with dimension-fitted generic models. Appearance is a design interpretation." : "MEP recognition stays in survey review. Studio imports accepted results; add or replace unknown equipment with shapes. It does not invent hidden connections.").font(.caption).foregroundStyle(.secondary)
                }
            }.disabled(busy)
            .navigationTitle("Design")
            .toolbar { ToolbarItem(placement:.primaryAction) { if let onSettings { Button("Settings",systemImage:"person.crop.circle",action:onSettings).labelStyle(.iconOnly) } } }
            .toolbar { ToolbarItem(placement: .cancellationAction) { if !embedded { Button("Done") { dismiss() }.disabled(busy) } } }
        }
        #if os(macOS)
        .frame(minWidth: 800,minHeight: 650)
        #endif

        .task(id:store.location.documentsURL) {
            // Technical surveys own their local library independently of House iCloud switching.
            let library = TechnicalRoomLibraryStore()
            technical = library
            do { try library.reload(); try await loadDesigns() } catch { self.error = error.localizedDescription }
        }
        .onAppear { active = true }
        .onDisappear { active = false; loadRequest = UUID() }
        .studioPresentation(item: $launch,onDismiss: { Task { do { try await loadDesigns() } catch { if active { self.error = error.localizedDescription } } } }) { launch in
            NavigationStack { StudioProjectView(seed: launch.document,storageRoot: launch.root ?? store.location.documentsURL) }
        }
        .alert("Studio",isPresented: Binding(get: { error != nil },set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private var filteredDesigns: [SceneEditDocument] { designs.filter { mode == .technical ? $0.source == .technical : $0.source != .technical } }
    private func hasDesign(_ source:SceneEditDocument.Source,id:UUID,root:URL) -> Bool {
        designs.contains { design in
            design.source == source && design.sourceID == id &&
                designRoots[DesignRef(design).id]?.standardizedFileURL == root.standardizedFileURL
        }
    }
    private func projectButton(_ title: String,icon: String,action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title,systemImage: icon)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }.frame(maxWidth: .infinity,alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Open design: "+title)
    }
    private func openHouse(_ record: HouseRecord) {
        do {
            let house = try store.house(for: record)
            var document = SceneEditDocument.seed(house: house,source: .house,id: record.id,scans: try HousePackage.readStructure(from: store.packageURL(for: record))?.rooms ?? [])
            document.includeRadiators(try HousePackage.readRadiators(from: store.packageURL(for: record))?.radiators ?? [])
            try document.validate(); launch = Launch(document: document)
        } catch { self.error = error.localizedDescription }
    }
    private func openRoom(_ record: RoomRecord) {
        do {
            let scan = try RoomPackage.readScan(from: store.packageURL(for: record))
            let document = SceneEditDocument.seed(house: House(room: try store.plan(for: record)),source: .room,id: record.id,scans: scan.map { [$0] } ?? [])
            try document.validate(); launch = Launch(document: document)
        } catch { self.error = error.localizedDescription }
    }
    private func openTechnical(_ id: UUID) {
        guard let technical,!busy else { return }; busy = true
        let primary = store.location.documentsURL
        Task { @MainActor in
            defer { busy = false }
            do {
                let package = try await technical.read(id)
                let document = try await BackgroundWork.run { try SceneEditDocument.technical(package) }
                guard active,!Task.isCancelled,self.technical === technical,primary == store.location.documentsURL else { return }
                launch = Launch(document: document,root: technical.root.deletingLastPathComponent())
            } catch { if active,!Task.isCancelled,self.technical === technical,primary == store.location.documentsURL { self.error = error.localizedDescription } }
        }
    }
    private func loadDesigns() async throws {
        let primary = store.location.documentsURL
        let local = technical?.root.deletingLastPathComponent() ?? StorageLocation.local().documentsURL
        let roots = primary.standardizedFileURL == local.standardizedFileURL ? [primary] : [primary,local]
        let request = UUID(); loadRequest = request
        let loaded:[SceneEditCatalogue.Entry]
        do { loaded = try await BackgroundWork.run(priority:.utility) { try SceneEditCatalogue.load(roots:roots) } }
        catch is CancellationError { return }
        catch {
            guard active,!Task.isCancelled,request == loadRequest,primary == store.location.documentsURL else { return }
            throw error
        }
        guard active,!Task.isCancelled,request == loadRequest,primary == store.location.documentsURL,
              local == (technical?.root.deletingLastPathComponent() ?? StorageLocation.local().documentsURL) else { return }
        designs = loaded.map(\.document)
        designRoots = Dictionary(uniqueKeysWithValues:loaded.map { ($0.id,$0.root) })
    }
}

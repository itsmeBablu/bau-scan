import SwiftUI

struct StudioLibraryView: View {
    @Environment(RoomStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var mode = Mode.house
    @State private var technical: TechnicalRoomLibraryStore?
    @State private var launch: Launch?
    @State private var designs: [SceneEditDocument] = []
    @State private var designRoots: [UUID:URL] = [:]
    @State private var error: String?
    @State private var busy = false
    enum Mode: String,CaseIterable { case house = "House", technical = "Technik Room" }
    private struct Launch: Identifiable { let id = UUID(); let document: SceneEditDocument; var root: URL? = nil }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Studio mode",selection: $mode) { ForEach(Mode.allCases,id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    Text("Create a separate design from a saved scan. Original scans, measurements and survey evidence remain unchanged.").font(.callout).foregroundStyle(.secondary)
                }
                if !filteredDesigns.isEmpty {
                    Section("Saved designs") {
                        ForEach(filteredDesigns,id: \.sourceID) { document in
                            projectButton(document.title,icon: "square.stack.3d.up") { launch = Launch(document: document,root: designRoots[document.sourceID]) }
                        }
                    }
                }
                if mode == .house {
                    Section("Start from a House scan") {
                        ForEach(store.houseRecords) { record in
                            projectButton(record.name,icon: "house") { openHouse(record) }
                        }
                        if store.houseRecords.isEmpty { Text("Saved House scans will appear here.").foregroundStyle(.secondary) }
                    }
                    Section("Start from a room scan") {
                        ForEach(store.records) { record in
                            projectButton(record.name,icon: "square.dashed") { openRoom(record) }
                        }
                    }
                } else {
                    Section("Start from a Technik Room survey") {
                        ForEach(technical?.records ?? []) { record in
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
            .navigationTitle("Design Studio")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(busy) } }
        }
        #if os(macOS)
        .frame(minWidth: 800,minHeight: 650)
        #endif
        .tint(.blue)
        .task {
            // Technical surveys own their local library independently of House iCloud switching.
            let library = TechnicalRoomLibraryStore()
            technical = library
            do { try library.reload(); try await loadDesigns() } catch { self.error = error.localizedDescription }
        }
        .sheet(item: $launch,onDismiss: { Task { try? await loadDesigns() } }) { launch in
            NavigationStack { StudioProjectView(seed: launch.document,storageRoot: launch.root ?? store.location.documentsURL) }
        }
        .alert("Studio",isPresented: Binding(get: { error != nil },set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private var filteredDesigns: [SceneEditDocument] { designs.filter { mode == .technical ? $0.source == .technical : $0.source != .technical } }
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
        guard let technical else { return }; busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let package = try await technical.read(id)
                let document = try await Task.detached { try SceneEditDocument.technical(package) }.value
                launch = Launch(document: document,root: technical.root.deletingLastPathComponent())
            } catch { self.error = error.localizedDescription }
        }
    }
    private func loadDesigns() async throws {
        let primary = store.location.documentsURL
        let local = technical?.root.deletingLastPathComponent() ?? StorageLocation.local().documentsURL
        let roots = primary.standardizedFileURL == local.standardizedFileURL ? [primary] : [primary,local]
        let loaded = try await Task.detached {
            var results: [(SceneEditDocument,URL)] = []
            for documents in roots {
              let root = documents.appendingPathComponent("SceneEdits",isDirectory: true)
              guard FileManager.default.fileExists(atPath: root.path) else { continue }
              let files = try FileManager.default.contentsOfDirectory(at: root,includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.prefix(200)
            for file in files {
                let name = file.deletingPathExtension().lastPathComponent
                guard let separator = name.firstIndex(of: "-"),let source = SceneEditDocument.Source(rawValue: String(name[..<separator])),let id = UUID(uuidString: String(name[name.index(after: separator)...])) else { continue }
                if let value = try SceneEditStore.read(file,source: source,id: id),!results.contains(where: { $0.0.source == source && $0.0.sourceID == id }) { results.append((value,documents)) }
            }
            }
            return results.sorted { $0.0.title.localizedStandardCompare($1.0.title) == .orderedAscending }
        }.value
        designs = loaded.map { $0.0 }
        designRoots = Dictionary(loaded.map { ($0.0.sourceID,$0.1) },uniquingKeysWith: { first,_ in first })
    }
}

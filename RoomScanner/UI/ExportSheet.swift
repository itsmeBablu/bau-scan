import SwiftUI

/// Export sheet for room or house (`ExportSubject`): format picker, generation in temporary folder,
/// sharing (`ShareLink`), saving via system file exporter,
/// or copies into `Exports/` folder of current storage.
struct ExportSheet: View {
    @AppStorage("renovation.proDetails") private var proDetails = false
    @Environment(RoomStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let subject: ExportSubject
    var initialFormat: ExportFormat? = nil

    init(subject: ExportSubject, initialFormat: ExportFormat? = nil) { self.subject = subject; self.initialFormat = initialFormat }
    init(record: RoomRecord, plan: FloorPlan, packageURL: URL?, initialFormat: ExportFormat? = nil) {
        self.init(subject: ExportSubject(record: record, plan: plan, packageURL: packageURL), initialFormat: initialFormat)
    }

    @State private var selected: ExportFormat = .pdf
    @State private var result: URL?
    @State private var working = false
    @State private var error: String?
    @State private var savingWithPicker = false
    @State private var savedToExports = false

    @State private var meshSource: ExportService.MeshSource = .parametric
    @State private var showingRevit = false

    private var formats: [ExportFormat] { ExportService.availableFormats(for: subject) }
    private var hasScanMesh: Bool { subject.usdzMeshURL != nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section {
                        Button { showingRevit = true } label: { Label("IFC (Revit)",systemImage:"building.2") }
                    }
                    ForEach(ExportFormat.Group.allCases) { group in
                        let items = formats.filter { $0.group == group && (proDetails || $0 != .json) }
                        if !items.isEmpty {
                            Section(LocalizedStringKey(group.titleKey)) {
                                ForEach(items) { format in
                                    Button { select(format) } label: { row(format) }
                                        .buttonStyle(.plain)
                                }
                                if group == .threeD, hasScanMesh {
                                    Picker("export.meshSource", selection: $meshSource) {
                                        ForEach(ExportService.MeshSource.allCases) { Text(LocalizedStringKey($0.titleKey)).tag($0) }
                                    }
                                    .onChange(of: meshSource) { _, _ in select(selected) }
                                }
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                Divider()
                footer
            }
            .navigationTitle("export.title")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("common.close") { dismiss() } } }
            .fileExporter(isPresented: $savingWithPicker, items: result.map { [$0] } ?? [], contentTypes: [result?.pathExtension == "zip" ? .zip : selected.utType]) { outcome in
                if case .failure(let e) = outcome { error = e.localizedDescription }
            }
        }
        .onAppear { select(initialFormat ?? selected) }
        .sheet(isPresented:$showingRevit) { RevitExportPanel(subject:subject) }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    /// Fixed footer: generated file + action buttons. Stays visible while list scrolls.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if working {
                    ProgressView().controlSize(.small)
                    Text("export.generating").foregroundStyle(.secondary)
                } else if let result {
                    Image(systemName: "doc").foregroundStyle(.secondary)
                    Text(result.lastPathComponent).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
            }
            .font(.callout)
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            HStack {
                if let result, !working {
                    ShareLink(item: result) { Label("export.share", systemImage: "square.and.arrow.up") }
                    Button { savingWithPicker = true } label: { Label("export.saveAs", systemImage: "folder") }
                    Button { saveToExports(result) } label: {
                        Label(savedToExports ? (store.isCloud ? "export.savedToCloud" : "export.savedToExports")
                                             : (store.isCloud ? "export.saveToCloud" : "export.saveToExports"),
                              systemImage: savedToExports ? "checkmark.circle" : (store.isCloud ? "icloud.and.arrow.up" : "arrow.down.doc"))
                    }.disabled(savedToExports)
                    #if os(macOS)
                    OpenWithMenu(fileURL: result, type: result.pathExtension == "zip" ? .zip : selected.utType).fixedSize()
                    #endif
                }
                Spacer()
            }
            .controlSize(.regular)
        }
        .padding()
        #if os(macOS)
        .background(.bar)
        #endif
    }

    private func row(_ format: ExportFormat) -> some View {
        HStack {
            Image(systemName: format.systemImage).frame(width: 24).foregroundStyle(.tint)
            VStack(alignment: .leading) {
                Text(LocalizedStringKey(format.titleKey))
                Text(LocalizedStringKey(format.descriptionKey)).font(.caption).foregroundStyle(.secondary)
                if LevelExportService.needsArchive(house:subject.house,format:format) { Text("Multiple levels: one file per level in a ZIP archive.").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if format == selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
        }
        .contentShape(Rectangle())
    }

    private func select(_ format: ExportFormat) {
        selected = format
        result = nil; error = nil; savedToExports = false; working = true
        let subject = self.subject
        var service = ExportService(); service.meshSource = meshSource
        Task.detached(priority: .userInitiated) { [service] in
            let outcome = Result { try service.export(subject, format: format) }
            await MainActor.run {
                guard selected == format else { return }
                working = false
                switch outcome {
                case .success(let url): result = url
                case .failure(let e): error = e.localizedDescription
                }
            }
        }
    }

    private func saveToExports(_ url: URL) {
        do {
            try store.saveExport(url, for: subject)
            savedToExports = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Registration adapter only. The IFC implementation imports Foundation exclusively.
private struct RevitExportPanel: View {
    let subject: ExportSubject
    @State private var architecture = true
    @State private var mep = true
    @State private var legacy = false
    @State private var importing = false
    @State private var surveys: [RevitTechnicalRoomInput] = []
    @State private var result: URL?
    @State private var error: String?
    @State private var working = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Architecture",isOn:$architecture)
                    Toggle("MEP",isOn:$mep)
                    Toggle("IFC2x3 compatibility",isOn:$legacy)
                }
                if mep {
                    Section("Technical rooms") {
                        Button("Select technical-room packages") { importing = true }
                        ForEach(surveys,id:\.document.room.id) { Text($0.name) }
                        if !surveys.isEmpty { Button("Clear selection") { surveys = []; result = nil } }
                    }
                }
                Section {
                    Button("Generate IFC") { generate() }.disabled(working || (!architecture && !mep))
                    if working { ProgressView() }
                    if let result { ShareLink("Save or share IFC",item:result) }
                    if let error { Text(error).foregroundStyle(.red) }
                    Text("Capture-derived data: device validation pending. Storey elevations use retained floor evidence when available; otherwise they are labelled estimates.").font(.caption)
                }
            }.formStyle(.grouped).disabled(working).navigationTitle("IFC (Revit)")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() }.disabled(working) } }
        }
        .fileImporter(isPresented:$importing,allowedContentTypes:[.technicalRoom],allowsMultipleSelection:true) { outcome in
            do {
                var loaded: [RevitTechnicalRoomInput] = []
                for url in try outcome.get() {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    let package = try TechnicalRoomPackage.read(from:url)
                    loaded.append(.init(name:package.manifest.name,document:package.document))
                }
                surveys = loaded
                result = nil
            } catch { self.error = error.localizedDescription }
        }
        .onChange(of:architecture) { _,_ in result = nil }
        .onChange(of:mep) { _,_ in result = nil }
        .onChange(of:legacy) { _,_ in result = nil }
        #if os(macOS)
        .frame(minWidth:440,minHeight:440)
        #endif
    }
    private func generate() {
        working = true
        result = nil
        error = nil
        let house = subject.house
        let selected = mep ? surveys : []
        let includeHouse = architecture
        var options = RevitExportOptions()
        options.includeArchitecture = architecture
        options.includeMEP = mep
        options.schema = legacy ? .ifc2x3 : .ifc4
        let evidenceURL = subject.kind == .house ? subject.usdzURL?.deletingLastPathComponent().appendingPathComponent("structure.json") : nil
        Task {
            do {
                let url = try await Task.detached(priority:.userInitiated) {
                    var effective = options
                    if let evidenceURL,FileManager.default.fileExists(atPath:evidenceURL.path) {
                        effective = try RevitScanEvidence.options(house:house,structureData:Data(contentsOf:evidenceURL),base:effective)
                    }
                    let data = try RevitIFCExporter.export(house:includeHouse ? house : nil,technicalRooms:selected,options:effective)
                    let directory = try ExportService.scratchDirectory()
                    let url = directory.appendingPathComponent("Survey.ifc")
                    try data.write(to:url,options:.atomic)
                    return url
                }.value
                result = url
            } catch { self.error = error.localizedDescription }
            working = false
        }
    }
}

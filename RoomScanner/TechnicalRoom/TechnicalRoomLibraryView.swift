import SwiftUI
import UniformTypeIdentifiers
import ImageIO
#if os(macOS)
import AppKit
#endif

struct TechnicalRoomLibraryView: View {
    @State private var library = TechnicalRoomLibraryStore()
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var error: String?
    @State private var deletion: UUID?
    @State private var path: [UUID] = []
    var embedded = false
    var onRequestScan: (() -> Void)? = nil
    var refreshToken = 0
    @State private var search = ""
    var initialSelection: UUID?
    var importURL: URL?

    private var scanningSupported: Bool {
        #if os(iOS)
        ScanCoordinator.isSupported
        #else
        false
        #endif
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if library.records.isEmpty {
                    ContentUnavailableView {
                        Label("No technical surveys",systemImage: "cube.transparent")
                    } description: {
                        Text("Capture equipment, pipes and ducts in a Technik Room.")
                    } actions: {
                        if let onRequestScan { Button("Scan Technik Room",action: onRequestScan).dsProminentControl().disabled(!scanningSupported) }
                    }.listRowBackground(Color.clear)
                }
                ForEach(library.records.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { record in
                    NavigationLink(value: record.id) {
                        HStack(spacing: 14) {
                            Image(systemName: "cube.transparent").font(.title2).foregroundStyle(.tint)
                                .frame(width: 64,height: 64).background(.quaternary,in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading,spacing: 4) {
                                Text(record.name).font(.headline)
                                Text(record.modifiedAt, format: .dateTime.day().month().year()).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical,6)
                    }
                    .contextMenu { Button("Delete", role: .destructive) { deletion = record.id } }
                    .swipeActions { Button("Delete", role: .destructive) { deletion = record.id } }
                }
                if !library.loadWarnings.isEmpty {
                    Section("Items requiring attention") { ForEach(library.loadWarnings, id: \.self) { Text($0).font(.caption) } }
                }
            }
            .listStyle(.plain)
            .searchable(text: $search,prompt: "Search technical surveys")
            .navigationTitle(embedded ? "Technik" : "Technical Rooms")
            .navigationDestination(for: UUID.self) { id in TechnicalStoredRoomView(id: id, library: library) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { if !embedded { Button("Done") { dismiss() } } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if let onRequestScan { Button { onRequestScan() } label: { Label("Scan Technik Room",systemImage: "camera.viewfinder") }.disabled(!scanningSupported) }
                        Button { beginImport() } label: { Label("Import survey",systemImage: "square.and.arrow.down") }
                    } label: { Label("Add survey",systemImage: "plus") }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 500)
        #endif

        .onAppear { do { try library.reload() } catch { self.error = error.localizedDescription } }
        .task(id: refreshToken) {
            do {
                try library.reload()
                if let importURL { path = [try await library.importPackage(importURL)] }
                else if let initialSelection { path = [initialSelection] }
            }
            catch { self.error = error.localizedDescription }
        }
        // Older packages may reach a Mac before Launch Services recognises the custom UTI.
        // Accept a directory as a fallback; the package reader still validates its full schema.
        .fileImporter(isPresented: $importing, allowedContentTypes: [.technicalRoom,.folder]) { result in
            Task { @MainActor in
                do { path = [try await library.importPackage(result.get())] }
                catch { self.error = error.localizedDescription }
            }
        }
        .confirmationDialog("Delete this technical survey?", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
            Button("Move to library trash", role: .destructive) {
                do { if let deletion { try library.delete(deletion) }; deletion = nil }
                catch { self.error = error.localizedDescription }
            }
        } message: { Text("The survey is moved to the library’s hidden .Trash folder and can be recovered manually.") }
        .alert("Technical Rooms", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func beginImport() {
        #if os(macOS)
        // SwiftUI's mixed file/directory importer can leave Open disabled for a legacy package.
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.technicalRoom,.package,.folder]
        panel.begin { response in
            guard response == .OK,let url = panel.url else { return }
            Task { @MainActor in
                do { path = [try await library.importPackage(url)] }
                catch { self.error = error.localizedDescription }
            }
        }
        #else
        importing = true
        #endif
    }
}

private struct TechnicalPackageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.technicalRoom] }
    let wrapper: FileWrapper
    init(url: URL) throws { wrapper = try FileWrapper(url: url, options: .immediate) }
    init(configuration: ReadConfiguration) throws { wrapper = configuration.file }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { wrapper }
}

private struct TechnicalExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct TechnicalStoredRoomView: View {
    @AppStorage("renovation.proDetails") private var proDetails = false
    let id: UUID
    let library: TechnicalRoomLibraryStore
    @State private var package: TechnicalRoomPackage?
    @State private var error: String?
    @State private var busy = false
    @State private var exporting = false
    @State private var exportDocument: TechnicalPackageDocument?
    @State private var meshExporting = false
    @State private var meshDocument: TechnicalExportDocument?
    @State private var meshType: UTType = .data
    @State private var meshFilename = "Technical Room"
    @State private var note = ""
    @State private var success = ""
    @State private var tab = Tab.scan
    @State private var studioDocument: SceneEditDocument?
    private enum Tab: Hashable { case scan, details, recognition }
    #if os(iOS)
    @State private var resuming = false
    #endif

    var body: some View {
        Group {
            if let package {
                VStack(spacing: 0) {
                    Picker("Saved survey view", selection: $tab) {
                        Text("3D scan").tag(Tab.scan)
                        Text("Survey details").tag(Tab.details)
                        Text(proDetails ? "MEP review" : "Find objects").tag(Tab.recognition)
                    }
                    .pickerStyle(.segmented).labelsHidden().padding(.horizontal).padding(.vertical, 8)
                    if tab == .scan { TechnicalSavedScanView(package: package,onPhotoLink: savePhotoLink) }
                    else if tab == .details { editor }
                    else {
                        TechnicalMEPReviewView(package: Binding(get: { self.package ?? package },set: { self.package = $0 }),persist: saveRecognition)
                    }
                }
            }
            else if let error { ContentUnavailableView(error, systemImage: "exclamationmark.triangle") }
            else { ProgressView("Opening saved survey…") }
        }
        .navigationTitle(package?.manifest.name ?? "Technical survey")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    guard let package else { return }
                    busy = true
                    Task { @MainActor in
                        defer { busy = false }
                        do { studioDocument = try await Task.detached { try SceneEditDocument.technical(package) }.value }
                        catch { self.error = error.localizedDescription }
                    }
                } label: { Label("Open in Design",systemImage: "square.stack.3d.up") }.disabled(package == nil || busy)
            }
            ToolbarItem(placement: .primaryAction) {
                if tab == .details { Button("Save") { save() }.disabled(package == nil || busy) }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("Export", systemImage: "square.and.arrow.up") {
                    Button("Full survey package") { save(exportAfter: true) }
                    if proDetails { Button("Editable technical survey JSON") { exportSurveyJSON() } }
                    ForEach(TechnicalMeshExporter.Format.allCases, id: \.self) { format in
                        Button(format.rawValue.uppercased()) { exportMesh(format) }
                    }
                    Menu(proDetails ? "Accepted MEP elements" : "Confirmed objects") {
                        ForEach(TechnicalMeshExporter.Format.allCases,id: \.self) { format in
                            Button(format.rawValue.uppercased()) { exportMesh(format,acceptedMEPOnly: true) }
                        }
                    }.disabled(package?.recognition.suggestions.contains(where: { $0.status == .accepted }) != true)
                    Text("DWG requires conversion from DXF in a CAD application.")
                }.labelStyle(.iconOnly).disabled(package == nil || busy)
            }
        }
        .task {
            do { package = try await library.read(id) } catch { self.error = error.localizedDescription }
        }
        .studioPresentation(item: $studioDocument) { document in
            NavigationStack { StudioProjectView(seed: document,storageRoot: library.root.deletingLastPathComponent()) }
        }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .technicalRoom,
                      defaultFilename: package?.manifest.name ?? "Technical Room") { result in
            if case .failure(let failure) = result { error = failure.localizedDescription }
        }
        .fileExporter(isPresented: $meshExporting, document: meshDocument, contentType: meshType,
                      defaultFilename: meshFilename) { result in
            if case .failure(let failure) = result { error = failure.localizedDescription }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $resuming) {
            if let current = package {
                TechnicalRoomScanView(restoring: current) { _ in
                    Task { @MainActor in
                        do { package = try await library.read(id) } catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
        #endif
        .alert("Technical survey", isPresented: Binding(get: { error != nil && package != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
    private var editor: some View {
        Form {
            Section("Survey") {
                TextField("Name", text: Binding(get: { package?.manifest.name ?? "" }, set: { package?.manifest.name = $0 }))
                Text("Stored survey — live alignment is not verified. Manual edits do not establish engineering accuracy.").font(.caption)
                Text(success).font(.caption).foregroundStyle(.secondary)
                #if os(iOS)
                Button("Resume AR survey from saved map") { resuming = true }.disabled(package?.worldMapData == nil || busy)
                if package?.worldMapData == nil {
                    Text("No recovery map was saved, so aligned AR capture cannot resume. You can still open the saved geometry in the 3D scan tab.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                #endif
            }
            if let current = package {
                if proDetails {
                Section("Capture evidence") {
                    if let png = current.thumbnailPNG { TechnicalStoredPhoto(data: png, name: "Survey thumbnail").id(current.manifest.modifiedAt) }
                    Text("\(current.journal.frames.count) frame records · \(current.journal.depths.count) depth · \(current.journal.meshes.count) mesh snapshots")
                    Text("\(current.evidence.keyframes.count) calibrated colour/depth images · \(current.recognition.suggestions.filter { $0.status == .accepted }.count) accepted MEP elements")
                    if current.evidence.droppedKeyframes > 0 { Text("\(current.evidence.droppedKeyframes) earlier viewpoints replaced within the image budget.").font(.caption) }
                    Text("\(current.alignment.checkpoints.count) checkpoint observations")
                    Text(current.worldMapData == nil ? "No saved world map" : "Recovery map retained")
                    if current.journal.retentionLimited { Text("Some older capture records exceeded retention limits.").foregroundStyle(.orange) }
                }
                }
                Section("Pipes — manual dimensions") {
                    ForEach(Array(current.document.room.pipeRuns.enumerated()), id: \.element.id) { index, pipe in
                        VStack(alignment: .leading) {
                            Text("\(pipe.medium.value.rawValue) · \(current.document.correctedLength(current.document.effectiveRoom.pipeRuns[index].length.value), specifier: "%.3f") m")
                            TextField("Outside diameter (mm)", value: pipeBinding(index, insulation: false), format: .number)
                            TextField("Insulation (mm)", value: pipeBinding(index, insulation: true), format: .number)
                        }
                    }
                }
                Section("Equipment") {
                    ForEach(Array(current.document.room.equipment.enumerated()), id: \.element.id) { index, item in
                        VStack(alignment: .leading) {
                            Text(item.name.value)
                            TextField("Width (m)", value: equipmentBinding(index, axis: 0), format: .number)
                            TextField("Height (m)", value: equipmentBinding(index, axis: 1), format: .number)
                            TextField("Depth (m)", value: equipmentBinding(index, axis: 2), format: .number)
                        }
                    }
                }
                Section("Annotations") {
                    Text("\(current.document.ducts.count) duct routes · \(current.document.room.fittings.count) fittings · \(current.document.connections.count) connections")
                    ForEach(current.document.measurements) { measurement in Text("\(measurement.name): \(current.document.correctedLength(measurement.length), specifier: "%.3f") m") }
                    ForEach(current.document.connectionWarnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                }
                Section("Notes and photos") {
                    ForEach(Array(current.document.room.notes.enumerated()), id: \.offset) { _, note in Text(note.value) }
                    TextField("Add survey note", text: $note, axis: .vertical)
                    Text("\(current.document.photoAssets.count) photos retained in package")
                    DisclosureGroup("View survey photos") {
                        ForEach(current.document.photoAssets) { photo in TechnicalStoredPhoto(data: photo.jpegData, name: "Photo \(photo.id.uuidString.prefix(8))") }
                    }
                }
            }
        }.disabled(busy)
    }
    private func pipeBinding(_ index: Int, insulation: Bool) -> Binding<Double> {
        Binding(get: {
            guard let pipe = package?.document.room.pipeRuns[index] else { return 0 }
            return insulation ? (pipe.insulationThicknessMm?.value ?? 0) : pipe.outerDiameterMm.value
        }, set: { value in
            let entry = TechnicalValue(value: value, unit: "mm", source: .entered, method: "manualPostCaptureUpdateRequiresVerification", accuracyMm: nil)
            if insulation { package?.document.room.pipeRuns[index].insulationThicknessMm = entry }
            else { package?.document.room.pipeRuns[index].outerDiameterMm = entry }
        })
    }
    private func equipmentBinding(_ index: Int, axis: Int) -> Binding<Double> {
        Binding(get: {
            guard let size = package?.document.room.equipment[index].size.value else { return 0 }
            return [size.x, size.y, size.z][axis]
        }, set: { value in
            guard var size = package?.document.room.equipment[index].size.value else { return }
            if axis == 0 { size.x = value } else if axis == 1 { size.y = value } else { size.z = value }
            package?.document.room.equipment[index].size = .init(value: size, unit: "m", source: .entered, method: "manualPostCaptureUpdateRequiresVerification", accuracyMm: nil)
        })
    }
    private func save(exportAfter: Bool = false) {
        guard var value = package else { return }
        if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            value.document.room.notes.append(.init(value: note, unit: "text", source: .entered, method: "postCaptureSurveyNote", accuracyMm: nil))
        }
        value.manifest.modifiedAt = Date()
        // Stored manual edits cannot certify a live alignment check.
        value.manifest.checkpointAcceptedAtSave = false
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                try await library.save(value); package = value; note = ""; success = "Saved"
                if exportAfter { exportDocument = try TechnicalPackageDocument(url: library.url(for: id)); exporting = true }
            } catch { self.error = error.localizedDescription }
        }
    }

    private func exportSurveyJSON() {
        guard let current = package, !busy else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let data = try await Task.detached { try TechnicalRoomJSONExporter.handoff(for: current) }.value
                meshDocument = TechnicalExportDocument(data: data)
                meshType = .json
                meshFilename = current.manifest.name + "-survey.json"
                meshExporting = true
            } catch { self.error = error.localizedDescription }
        }
    }
    private func exportMesh(_ format: TechnicalMeshExporter.Format,acceptedMEPOnly: Bool = false) {
        guard let current = package else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: directory) }
                    let url = directory.appendingPathComponent("TechnicalRoom.\(format.rawValue)")
                    try TechnicalMeshExporter.write(current, format: format, to: url,acceptedMEPOnly: acceptedMEPOnly)
                    return try Data(contentsOf: url)
                }.value
                meshDocument = TechnicalExportDocument(data: data)
                meshType = UTType(filenameExtension: format.rawValue) ?? .data
                meshFilename = current.manifest.name + (acceptedMEPOnly ? "-MEP" : "") + "." + format.rawValue
                meshExporting = true
            } catch { self.error = error.localizedDescription }
        }
    }
    private func saveRecognition(_ value: TechnicalRoomPackage) async throws -> TechnicalRoomPackage {
        guard !busy else { throw TechnicalRoomPackage.PackageError.invalidPackage }
        busy = true
        defer { busy = false }
        var updated = value
        updated.manifest.modifiedAt = Date()
        updated.manifest.checkpointAcceptedAtSave = false
        try await library.save(updated)
        package = updated
        return updated
    }
    private func savePhotoLink(_ id: UUID,_ url: URL) async throws {
        guard var value = package else { throw TechnicalRoomPackage.PackageError.invalidPackage }
        try value.evidence.setGooglePhotosURL(url,for: id)
        _ = try await saveRecognition(value)
    }
}

private struct TechnicalStoredPhoto: View {
    let data: Data
    let name: String
    @State private var image: CGImage?
    var body: some View {
        VStack(alignment: .leading) {
            Text(name).font(.caption)
            if let image { Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 180) }
        }
        .task {
            if let source = CGImageSourceCreateWithData(data as CFData, nil) {
                image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 800, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
            }
        }
    }
}

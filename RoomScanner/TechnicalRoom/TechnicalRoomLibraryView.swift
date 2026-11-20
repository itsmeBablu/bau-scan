import SwiftUI
import UniformTypeIdentifiers
import ImageIO

struct TechnicalRoomLibraryView: View {
    @State private var library = TechnicalRoomLibraryStore()
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var error: String?
    @State private var deletion: UUID?
    @State private var path: [UUID] = []
    var initialSelection: UUID?
    var importURL: URL?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if library.records.isEmpty { Text("No saved technical surveys. Scan one Technik Room to begin.").foregroundStyle(.secondary) }
                ForEach(library.records) { record in
                    NavigationLink(value: record.id) {
                        VStack(alignment: .leading) {
                            Text(record.name).font(.headline)
                            Text(record.modifiedAt, format: .dateTime).font(.caption).foregroundStyle(.secondary)
                            Text("Device validation pending").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu { Button("Delete", role: .destructive) { deletion = record.id } }
                    .swipeActions { Button("Delete", role: .destructive) { deletion = record.id } }
                }
                if !library.loadWarnings.isEmpty {
                    Section("Items requiring attention") { ForEach(library.loadWarnings, id: \.self) { Text($0).font(.caption) } }
                }
            }
            .navigationTitle("Technical Rooms")
            .navigationDestination(for: UUID.self) { id in TechnicalStoredRoomView(id: id, library: library) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("Import") { importing = true } }
            }
        }
        .frame(minWidth: 320, minHeight: 450)
        .task {
            do {
                try library.reload()
                if let importURL { path = [try await library.importPackage(importURL)] }
                else if let initialSelection { path = [initialSelection] }
            }
            catch { self.error = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.technicalRoom]) { result in
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
}

private struct TechnicalPackageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.technicalRoom] }
    let wrapper: FileWrapper
    init(url: URL) throws { wrapper = try FileWrapper(url: url, options: .immediate) }
    init(configuration: ReadConfiguration) throws { wrapper = configuration.file }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { wrapper }
}

private struct TechnicalStoredRoomView: View {
    let id: UUID
    let library: TechnicalRoomLibraryStore
    @State private var package: TechnicalRoomPackage?
    @State private var error: String?
    @State private var busy = false
    @State private var exporting = false
    @State private var exportDocument: TechnicalPackageDocument?
    @State private var note = ""
    @State private var success = ""
    #if os(iOS)
    @State private var resuming = false
    #endif

    var body: some View {
        Group {
            if package != nil { editor }
            else if let error { ContentUnavailableView(error, systemImage: "exclamationmark.triangle") }
            else { ProgressView() }
        }
        .navigationTitle(package?.manifest.name ?? "Technical survey")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Save") { save() }.disabled(package == nil || busy) }
            ToolbarItem(placement: .primaryAction) {
                Button("Export package") { Task { @MainActor in
                    save(exportAfter: true)
                } }.disabled(package == nil || busy)
            }
        }
        .task {
            do { package = try await library.read(id) } catch { self.error = error.localizedDescription }
        }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .technicalRoom,
                      defaultFilename: package?.manifest.name ?? "Technical Room") { result in
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
                #endif
            }
            if let current = package {
                Section("Capture evidence") {
                    if let png = current.thumbnailPNG { TechnicalStoredPhoto(data: png, name: "Survey thumbnail").id(current.manifest.modifiedAt) }
                    Text("\(current.journal.frames.count) frame records · \(current.journal.depths.count) depth · \(current.journal.meshes.count) mesh snapshots")
                    Text("\(current.alignment.checkpoints.count) checkpoint observations")
                    Text(current.worldMapData == nil ? "No saved world map" : "Recovery map retained")
                    if current.journal.retentionLimited { Text("Some older capture records exceeded retention limits.").foregroundStyle(.orange) }
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

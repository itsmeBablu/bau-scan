import SwiftUI
import AppKit

/// Native macOS export dialog for creating an organised package or photos-only ZIP archive.
struct OrganisedExportSheet: View {
    let subject: ExportSubject
    var photosOnly: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(RoomStore.self) private var store
    @AppStorage("measurementUnit") private var unit: MeasurementUnit = .both

    @State private var options = OrganisedExportService.Options()
    @State private var isExporting = false
    @State private var progress = 0.0
    @State private var progressStatus = ""
    @State private var exportTask: Task<Void, Never>?
    @State private var completedURL: URL?
    @State private var errorMessage: String?
    @State private var technicalRooms: [TechnicalRoomManifest] = []

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Image(systemName: photosOnly ? "photo.stack" : "archivebox")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(photosOnly ? "Export Photos Archive" : "Organised Project Package")
                        .font(.headline)
                    Text(subject.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top)

            Divider()

            if photosOnly {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Exports survey photos organised by level and room with an index.csv metadata table (scan coordinates, no GPS).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            } else {
                Form {
                    Picker("Export preset",selection:Binding(get:{ OrganisedExportPreset.matching(options) },set:{ preset in
                        preset.apply(to:&options)
                        if options.includeNativePackages { options.removePhotoMetadata = false }
                    })) {
                        ForEach(OrganisedExportPreset.allCases) { preset in Text(LocalizedStringKey(preset.rawValue)).tag(preset) }
                    }
                    Section("Include in ZIP Package") {
                        Toggle("Floor Plans (PDF, SVG, DXF)", isOn: $options.includePlans)
                        Toggle("3D Models (OBJ, STL, PLY, USDZ)", isOn: $options.includeModels)
                        Toggle("Utility Room Survey (JSON, Mesh, DXF)", isOn: $options.includeTechnicalRoom)
                        if options.includeTechnicalRoom {
                            Picker("Include utility room",selection:$options.technicalRoomID) {
                                Text("None").tag(Optional<UUID>.none)
                                ForEach(technicalRooms) { room in Text(room.name).tag(Optional(room.id)) }
                            }
                            DisclosureGroup("Additional utility rooms") {
                                ForEach(technicalRooms) { room in
                                    Toggle(room.name,isOn:Binding(get:{ options.additionalTechnicalRoomIDs.contains(room.id) },set:{ selected in
                                        if selected { options.additionalTechnicalRoomIDs.insert(room.id) }
                                        else { options.additionalTechnicalRoomIDs.remove(room.id) }
                                    }))
                                }
                            }
                        }
                        Toggle("Survey Photos (optional)", isOn: $options.includePhotos)
                        Toggle("Design Studio Layout", isOn: $options.includeStudio)
                        Toggle("IFC (Revit)",isOn:$options.includeIFC)
                        if options.includeIFC {
                            Toggle("Include house architecture in IFC",isOn:$options.includeArchitectureIFC)
                            Text("Technical IFC files use independent room coordinates. No house registration is assumed.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Toggle("Include native scan packages",isOn:$options.includeNativePackages)
                            .onChange(of:options.includeNativePackages) { _,enabled in if enabled { options.removePhotoMetadata = false } }
                    }
                }
                .formStyle(.grouped)
                .frame(minHeight:220).disabled(isExporting)
            }

            if options.includePhotos || photosOnly {
                Toggle("Remove photo metadata from export copies",isOn:$options.removePhotoMetadata)
                    .padding(.horizontal).disabled(isExporting || options.includeNativePackages)
                Text("Re-encodes JPEG copies without EXIF/GPS metadata. Camera poses remain in the photo index.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            }
            if options.includeNativePackages {
                Text("Native backups preserve original photo metadata and source assets.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            }

            HStack {
                Text("Estimated size: \(formatBytes(OrganisedExportService.estimateSize(subject: subject, options: options, storageRoot: store.location.documentsURL)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)

            if isExporting {
                VStack(spacing: 6) {
                    ProgressView(value: progress, total: 1.0)
                    HStack {
                        Text(progressStatus)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") {
                            exportTask?.cancel()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal)
            }

            Divider()

            HStack {
                Button("common.cancel") {
                    dismiss()
                }
                .disabled(isExporting)

                Spacer()

                Button(photosOnly ? "Export Photos (ZIP)…" : "Export Package (ZIP)…") {
                    startExport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting || (!photosOnly && !options.includePlans && !options.includeModels && !options.includeTechnicalRoom && !options.includePhotos && !options.includeStudio && !options.includeNativePackages && !options.includeIFC))
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(minWidth:420,idealWidth:480,maxWidth:720)
        .onAppear {
            options.photosOnly = photosOnly
            options.unit = unit
        }
        .task {
            let library = TechnicalRoomLibraryStore(root:store.location.documentsURL.appendingPathComponent("TechnicalRooms"))
            do { try library.reload(); technicalRooms = library.records }
            catch { errorMessage = error.localizedDescription }
        }
        .onDisappear { exportTask?.cancel() }
        .alert("Export Successful", isPresented: Binding(get: { completedURL != nil }, set: { if !$0 { completedURL = nil } })) {
            Button("Reveal in Finder") {
                if let url = completedURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                dismiss()
            }
            Button("Done") { dismiss() }
        } message: {
            Text("The ZIP archive was created successfully.")
        }
        .alert("Export Failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func startExport() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.zip]

        // Remember last folder
        let lastFolderKey = "OrganisedExportLastFolder"
        if let lastPath = UserDefaults.standard.string(forKey: lastFolderKey) {
            panel.directoryURL = URL(fileURLWithPath: lastPath)
        }

        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: Date())
        let stem = ArchivePath.component(subject.name, fallback: "Export")
        panel.nameFieldStringValue = photosOnly ? "\(stem)_photos_\(dateStr).zip" : "\(stem)_export_\(dateStr).zip"

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        // Save last directory
        UserDefaults.standard.set(destinationURL.deletingLastPathComponent().path, forKey: lastFolderKey)

        isExporting = true
        progress = 0.05
        progressStatus = AppLanguage.text("Preparing…")

        exportTask = Task { @MainActor in
            defer { isExporting = false; exportTask = nil }
            do {
                try await OrganisedExportService.export(
                    subject: subject,
                    options: options,
                    storageRoot: store.location.documentsURL,
                    progressHandler: { p, s in
                        Task { @MainActor in
                            self.progress = p
                            self.progressStatus = s
                        }
                    },
                    to: destinationURL
                )
                try Task.checkCancellation(); completedURL = destinationURL
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

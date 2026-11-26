import SwiftUI
import UniformTypeIdentifiers

/// Library shortcut into the existing exporters; no exports occur while loading.
struct ProjectScanExportSheet:View {
    let entry:ProjectLibraryEntry
    @Environment(\.dismiss) private var dismiss
    @State private var subject:ExportSubject?
    @State private var technical:TechnicalRoomPackage?
    @State private var error:String?
    var body:some View {
        Group {
            if let subject { ExportSheet(subject:subject) }
            else if let technical { TechnicalScanExportPanel(package:technical,name:entry.title) }
            else {
                NavigationStack {
                    Group {
                        if let error { ContentUnavailableView("Unable to complete action",systemImage:"exclamationmark.triangle",description:Text(error)) }
                        else { ProgressView("Opening scan…") }
                    }.toolbar { ToolbarItem(placement:.cancellationAction) { Button("Close") { dismiss() } } }
                }
            }
        }.task(id:entry.id) {
            do {
                let result = try await Task.detached(priority:.userInitiated) { () -> (ExportSubject?,TechnicalRoomPackage?) in
                    if entry.reference.kind == .technicalRoom { return (nil,try TechnicalRoomPackage.read(from:entry.url)) }
                    var subject:ExportSubject
                    if entry.reference.kind == .house {
                        subject = ExportSubject(record:try HousePackage.readRecord(from:entry.url),house:try HousePackage.readHouse(from:entry.url),packageURL:entry.url)
                    } else {
                        subject = ExportSubject(record:try RoomPackage.readRecord(from:entry.url),plan:try RoomPackage.readPlan(from:entry.url),packageURL:entry.url)
                    }
                    subject.name = entry.title; return (subject,nil)
                }.value
                guard !Task.isCancelled else { return }; subject = result.0; technical = result.1
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

private struct TechnicalScanExportPanel:View {
    let package:TechnicalRoomPackage
    let name:String
    @Environment(\.dismiss) private var dismiss
    @State private var format = TechnicalMeshExporter.Format.usdz
    @State private var working = false
    @State private var result:URL?
    @State private var saving = false
    @State private var error:String?
    @State private var task:Task<Void,Never>?
    @State private var request = UUID()
    var body:some View {
        NavigationStack {
            Form {
                Picker("Output",selection:$format) {
                    ForEach(TechnicalMeshExporter.Format.allCases,id:\.self) { Text($0.rawValue.uppercased()).tag($0) }
                }.disabled(working)
                Button("Generate",systemImage:"arrow.down.doc") { generate() }.disabled(working)
                if working { ProgressView("Working…") }
                if let result {
                    ShareLink(item:result) { Label("Share",systemImage:"square.and.arrow.up") }
                    Button("Save to Files",systemImage:"folder") { saving = true }
                }
                Text("Capture-derived data: device validation pending.").font(.caption)
                if let error { Text(error).font(.caption).foregroundStyle(DS.ColorToken.error.color) }
            }.navigationTitle("Export")
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Close") { dismiss() } } }
        }.onChange(of:format) { _,_ in result = nil; error = nil }
            .onDisappear { request = UUID(); task?.cancel(); task = nil; working = false }
            .fileExporter(isPresented:$saving,items:result.map { [$0] } ?? [],contentTypes:[UTType(filenameExtension:format.rawValue) ?? .data]) { outcome in
                if case .failure(let failure) = outcome { error = failure.localizedDescription }
            }
    }
    private func generate() {
        guard !working else { return }; working = true; result = nil; error = nil
        let token = UUID(),package = package,format = format,name = name; request = token
        task = Task {
            do {
                let url = try await BackgroundWork.run {
                    let file = try ExportService.scratchDirectory().appendingPathComponent(ArchivePath.component(name)+"."+format.rawValue)
                    try Task.checkCancellation(); try TechnicalMeshExporter.write(package,format:format,to:file); try Task.checkCancellation()
                    return file
                }
                guard !Task.isCancelled,request == token else { return }; result = url; working = false; task = nil
            } catch {
                guard !Task.isCancelled,request == token else { return }; self.error = error.localizedDescription; working = false; task = nil
            }
        }
    }
}

import SwiftUI

/// Independent project evidence; never configures an ARSession or rewrites a scan.
struct ProjectVoiceNotesView: View {
    let projectID: UUID
    var initialReference: ProjectReference? = nil
    var onClose: (() -> Void)? = nil
    @Environment(RenovationWorkspace.self) private var workspace
    @Environment(\.locale) private var locale
    @State private var notes: [ARNote] = []
    @State private var referenceID = ""
    @State private var operation = OperationLifetime()
    private var busy: Bool { operation.isRunning }
    @State private var reloadRequest = UUID()
    @State private var visible = false
    @State private var error: String?
    @State private var deleting: ARNote?
    @State private var editing: ARNote?
    @State private var recordingEditor:ARNote?
    @State private var query = ""
    @State private var sharing = false
    @State private var sharedAudio:URL?
    @State private var shareRequest = UUID()
    @State private var includeAudio = false
    @State private var exportURL: URL?
    @State private var recoveryCount = 0
    @State private var closing = false
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @State private var recorder = NoteAudioRecorder()
    @State private var failedClip: NoteAudioRecorder.Clip?
    @State private var clipReference: ProjectReference?
    @State private var clipRoot: URL?
    @State private var pendingID: UUID?
    @State private var staged = false
    #endif
    private var references: [ProjectReference] {
        workspace.project(projectID)?.references.filter { [.house,.room,.technicalRoom].contains($0.kind) } ?? []
    }
    private var voiceNotes:[ARNote] {
        notes.filter { $0.audioFileName != nil && (query.isEmpty || ($0.title ?? "").localizedCaseInsensitiveContains(query) || $0.text.localizedCaseInsensitiveContains(query)) }
            .sorted { ($0.audioModifiedAt ?? $0.createdAt) > ($1.audioModifiedAt ?? $1.createdAt) }
    }
    var body: some View {
        List {
            Section {
                Text("Voice notes stay in the selected library. No audio is sent to AI services.")
                    .font(.callout).foregroundStyle(.secondary)
                if let initialReference {
                    Label(workspace.entry(initialReference).map { workspace.title($0) } ?? "Current scan",systemImage: "link")
                    Text("Linked to this scan. No spatial pin is added.").font(.caption).foregroundStyle(.secondary)
                } else { Picker("Associated scan",selection:$referenceID) {
                    Text("None").tag("")
                    ForEach(references) { reference in
                        Text(workspace.entry(reference).map { workspace.title($0) } ?? reference.itemID.uuidString).tag(reference.id)
                    }
                }.disabled(busy || audioActive) }
                #if os(iOS)
                HStack(spacing:8) {
                    Button {
                        if recorder.recording { recorder.stop() } else { startRecording() }
                    } label: {
                        Image(systemName:recorder.recording ? "stop.fill" : "mic.fill")
                            .font(DS.Typography.body.weight(.semibold)).frame(width:44,height:44)
                    }.buttonStyle(.plain).foregroundStyle(recorder.recording ? .red : .primary)
                        .accessibilityLabel(recorder.recording ? "Stop and save" : "Record voice note")
                        .disabled(busy || recorder.preparing || (!recorder.recording && !references.contains { $0.id == referenceID }))
                    if recorder.recording {
                        HStack(spacing:2) {
                            ForEach(Array(recorder.levels.suffix(32).enumerated()),id:\.offset) { _,level in
                                Capsule().fill(.red).frame(width:3,height:max(3,CGFloat(level)*22))
                            }
                        }.frame(maxWidth:.infinity).frame(height:28)
                        Text(Duration.seconds(recorder.elapsed).formatted(.time(pattern:.minuteSecond))).font(.caption).monospacedDigit()
                        Button(recorder.paused ? "Resume recording" : "Pause recording",systemImage:recorder.paused ? "play.fill" : "pause.fill") {
                            if recorder.paused { recorder.resume() } else { recorder.pause() }
                        }.labelStyle(.iconOnly).frame(width:44,height:44)
                    } else { Text("Record voice note").font(.subheadline); Spacer() }
                }
                if let failedClip { Button("Retry saving recording") { saveClip(failedClip) }.disabled(busy) }
                #endif
                if !references.contains(where:{ $0.id == referenceID }) { Text("Select a scan before recording.").font(.caption).foregroundStyle(.secondary) }
                #if os(iOS)
                if audioActive || hasUnstagedClip {
                    Button("Discard unsaved recording",role:.destructive) { recorder.stop(cancel:true,reason:"Recording discarded"); failedClip = nil }
                }
                #endif
                if busy { ProgressView().accessibilityLabel("Saving voice note") }
                if recoveryCount > 0 {
                    Button("Recover unsaved recordings") { recoverRecordings() }.disabled(busy || audioActive)
                }
            }
            Section("Voice notes") {
                ForEach(voiceNotes) { note in
                    VStack(alignment:.leading,spacing:8) {
                        if note.audioFileName == nil { Text(note.title ?? note.stem).font(.headline) }
                        if !note.text.isEmpty { Text(note.text).textSelection(.enabled) }
                        Text(note.createdAt,format:.dateTime).font(.caption).foregroundStyle(.secondary)
                        if note.audioDuration != nil {
                            InlineVoiceNoteRow(note:note,root:workspace.notesRoot,
                                subtitle:workspace.entry(note.reference).map { workspace.title($0,locale:locale) } ?? note.reference.itemID.uuidString,
                        displayTitle:VoiceNoteDisplayName.title(note,summary:workspace.scanSummaries[note.reference.id],locale:locale),
                                enabled:!busy && !audioActive)
                        }
                    }.padding(.vertical,4).contextMenu {
                        Button("Rename or edit",systemImage:"pencil") { editing = note }
                        #if os(iOS)
                        Button("Re-record",systemImage:"mic") { NotePlayback.stopActive(); recordingEditor = note }
                        #endif
                        Button("Share recording",systemImage:"square.and.arrow.up") { shareAudio(note) }
                        Button("Delete",systemImage:"trash",role:.destructive) { deleting = note }
                    }.disabled(busy || audioActive)
                }
                if voiceNotes.isEmpty { Text("No voice notes yet").foregroundStyle(.secondary) }
            }
            Section("Export") {
                Toggle("Include voice audio in export",isOn:$includeAudio).disabled(busy)
                Button("Export voice notes ZIP") { exportNotes() }.disabled(busy || audioActive)
                if let exportURL { ShareLink(item:exportURL) }
            }
        }
        .navigationTitle("Voice notes")
        .searchable(text:$query,prompt:"Search voice notes")
        .task(id:projectID.uuidString+workspace.notesRoot.absoluteString) {
            visible = true
            if let initialReference { referenceID = initialReference.id }
            else if references.count == 1 { referenceID = references[0].id }
            await reload()
        }
        .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Close") { requestClose() } } }
        .confirmationDialog("Close voice notes?",isPresented:$closing,titleVisibility:.visible) {
            Button("Discard unsaved recording and close",role:.destructive) { finishClose() }
            Button("Cancel",role:.cancel) {}
        } message: { Text("Saved recordings stay in recovery. Only the active or unsaved clip is discarded.") }
        .sheet(item:$editing) { note in NoteTextEditor(note:note) { updated in try await saveEdit(updated,expected:note) } }
        .sheet(item:$recordingEditor,onDismiss:{ Task { await reload() } }) { note in
            VoiceNotePlayerSheet(note:note,root:workspace.notesRoot)
        }
        .sheet(isPresented:$sharing,onDismiss:{ shareRequest = UUID() }) {
            NavigationStack {
                Group {
                    if let sharedAudio { ShareLink(item:sharedAudio) { Label("Share recording",systemImage:"square.and.arrow.up") } }
                    else { ProgressView("Preparing recording…") }
                }.padding().navigationTitle("Share recording")
                    .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { sharing = false } } }
            }
        }
        .alert("Delete voice note?",isPresented:Binding(get:{ deleting != nil },set:{ if !$0 { deleting = nil } })) {
            Button("Delete",role:.destructive) { if let deleting { remove(deleting) }; deleting = nil }
            Button("Cancel",role:.cancel) { deleting = nil }
        }
        .alert("Error",isPresented:Binding(get:{ error != nil },set:{ if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        #if os(iOS)
        .navigationBarBackButtonHidden(audioActive || busy || (failedClip != nil && !staged))
        .interactiveDismissDisabled(audioActive || busy || (failedClip != nil && !staged))
        .onChange(of:recorder.error) { _,message in if let message { error = message; recorder.error = nil } }
        #endif
        .task(id:operation.id) {
            guard let request = operation.id else { return }
            do { try await Task.sleep(for:.seconds(30)) } catch { return }
            guard !Task.isCancelled,operation.warnIfRunning(request) else { return }
            error = AppLanguage.text("This operation is taking longer than expected. Please wait; recovery copies are kept.")
        }
        .onChange(of:references.map(\.id)) { _,_ in
            if !references.contains(where:{ $0.id == referenceID }),references.count == 1 { referenceID = references[0].id }
        }
        .onDisappear {
            visible = false
            reloadRequest = UUID()
            #if os(iOS)
            recorder.stop(partial:true); recorder.onClip = nil
            #endif
        }
    }
    private func requestClose() {
        if audioActive || busy || hasUnstagedClip { closing = true } else { finishClose() }
    }
    private func finishClose() {
        #if os(iOS)
        recorder.stop(cancel:true,reason:"Recording discarded"); failedClip = nil
        #endif
        if let onClose { onClose() } else { dismiss() }
    }
    private var audioActive: Bool {
        #if os(iOS)
        recorder.recording || recorder.preparing
        #else
        false
        #endif
    }
    private var hasUnstagedClip: Bool {
        #if os(iOS)
        failedClip != nil && !staged
        #else
        false
        #endif
    }
    @MainActor private func reload() async {
        let root = workspace.notesRoot, request = UUID()
        reloadRequest = request
        do {
            let index = try await Task.detached { try ARNoteStore.index(root:root,projectID:projectID) }.value
            guard !Task.isCancelled,visible,root == workspace.notesRoot,reloadRequest == request else { return }
            notes = index.notes
            let recoveryRoot = try VoiceNoteRecovery.root()
            let count = try await Task.detached { try ARNoteStore.index(root:recoveryRoot,projectID:projectID).notes.count }.value
            guard !Task.isCancelled,visible,root == workspace.notesRoot,reloadRequest == request else { return }
            recoveryCount = count
        } catch {
            guard !Task.isCancelled,visible,root == workspace.notesRoot,reloadRequest == request else { return }
            self.error = error.localizedDescription
        }
    }
    private func exportNotes() {
        let root = workspace.notesRoot,selected = references,audio = includeAudio
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("voice-notes-"+UUID().uuidString+".zip")
        guard let request = operation.begin() else { return }
        Task { @MainActor in
            defer { operation.finish(request) }
            do {
                try await Task.detached { try VoiceNotesExporter.export(root:root,projectID:projectID,references:selected,includeAudio:audio,to:target) }.value
                guard visible,root == workspace.notesRoot else { try? FileManager.default.removeItem(at:target); return }
                exportURL = target
            } catch { if visible,root == workspace.notesRoot { self.error = error.localizedDescription } }
        }
    }
    private func shareAudio(_ note:ARNote) {
        guard !busy,!audioActive else { return }
        let root = workspace.notesRoot
        let name = VoiceNoteDisplayName.title(note,summary:workspace.scanSummaries[note.reference.id],locale:locale)
        let request = UUID(); shareRequest = request
        sharedAudio = nil; sharing = true
        Task {
            do {
                let file = try await Task.detached(priority:.utility) {
                    let bytes = try ARNoteStore.audio(for:note,root:root)
                    let target = try ExportService.scratchDirectory().appendingPathComponent(ArchivePath.component(name)+".m4a")
                    try bytes.write(to:target,options:.atomic); return target
                }.value
                guard visible,sharing,shareRequest == request,root == workspace.notesRoot else { return }; sharedAudio = file
            } catch { guard visible,shareRequest == request else { return }; sharing = false; self.error = error.localizedDescription }
        }
    }
    private func recoverRecordings() {
        guard let request = operation.begin() else { return }
        let root = workspace.notesRoot,selected = references
        Task { @MainActor in
            defer { operation.finish(request) }
            do {
                try await Task.detached { try VoiceNoteRecovery.recover(projectID:projectID,from:VoiceNoteRecovery.root(),to:root,references:selected) }.value
                guard visible,root == workspace.notesRoot else { return }
                #if os(iOS)
                failedClip = nil; pendingID = nil; staged = false
                #endif
                await reload()
            } catch { if visible,root == workspace.notesRoot { self.error = error.localizedDescription } }
        }
    }
    @MainActor private func saveEdit(_ note:ARNote,expected:ARNote) async throws {
        guard note.projectID == projectID else { throw CocoaError(.fileWriteNoPermission) }
        let root = workspace.notesRoot
        var updated = note; updated.modifiedAt = Date()
        do {
            _ = try await NoteSaveWorker.text(updated,expected:expected,root:root)
            await reload()
        } catch { await reload(); throw error }
    }
    private func remove(_ note: ARNote) { mutate { $0.notes.removeAll { $0.id == note.id } } }
    private func mutate(_ edit: @escaping (inout ARNoteIndex) throws -> Void) {
        guard let request = operation.begin() else { return }
        let root = workspace.notesRoot
        Task { @MainActor in
            defer { operation.finish(request) }
            do {
                _ = try await Task.detached { try ARNoteStore.update(root:root,projectID:projectID,edit:edit) }.value
                guard visible,root == workspace.notesRoot else { return }
                await reload()
            } catch { if visible,root == workspace.notesRoot { self.error = error.localizedDescription } }
        }
    }
    #if os(iOS)
    private func startRecording() {
        guard let reference = references.first(where:{ $0.id == referenceID }) else { return }
        NotePlayback.stopActive(); clipReference = reference; clipRoot = workspace.notesRoot
        pendingID = nil; staged = false
        recorder.onClip = { clip in saveClip(clip) }
        Task { guard visible else { return }; await recorder.start() }
    }
    private func saveClip(_ clip: NoteAudioRecorder.Clip) {
        guard !busy,let reference = clipReference,let root = clipRoot else { failedClip = clip; return }
        let language = locale.identifier
        let id = pendingID ?? UUID(); pendingID = id
        guard let request = operation.begin() else { failedClip = clip; return }
        failedClip = clip
        Task { @MainActor in
            defer { operation.finish(request) }
            do {
                var note = ARNote(id:id,projectID:projectID,reference:reference,number:1,level:nil,roomID:reference.itemID,position:nil,planPosition:nil,language:language)
                note.audioFileName = note.stem+".m4a"; note.audioDuration = clip.duration; note.partial = clip.partial
                _ = try await NoteSaveWorker.newRecording(note,audio:clip.data,root:root,outbox:VoiceNoteRecovery.root())
                guard visible,root == workspace.notesRoot else { return }
                failedClip = nil; pendingID = nil; staged = false; await reload()
            } catch { if visible,root == workspace.notesRoot { self.error = error.localizedDescription } }
        }
    }
    #endif
}

/// Opens the existing local recording/recovery flow directly for a saved or
/// in-progress scan. Owns catalogue context so legacy entry points also work.
struct ScanVoiceNotesSheet: View {
    let reference: ProjectReference
    let location: StorageLocation
    var preferredProjectID: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var workspace = RenovationWorkspace()
    @State private var projectID: UUID?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Group {
                if let projectID {
                    ProjectVoiceNotesView(projectID: projectID,initialReference: reference,onClose: { dismiss() })
                } else if let error {
                    ContentUnavailableView("Could not open voice notes",systemImage: "mic.slash",description: Text(error))
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                } else { ProgressView("Opening voice notes…") }
            }
        }
        .environment(workspace)
        .task(id: reference.id) {
            await workspace.reload(location: location)
            guard !Task.isCancelled else { return }
            guard workspace.error == nil else { error = workspace.error; return }
            var owner: UUID?
            workspace.change { owner = try $0.voiceNotesProject(for: reference,preferredProjectID:preferredProjectID) }
            guard workspace.error == nil else { error = workspace.error; return }
            projectID = owner
            if projectID == nil { error = "The scan could not be associated with a project." }
        }
    }
}

struct NoteTextEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var note: ARNote
    private let initial:ARNote
    var save: (ARNote) async throws -> Void
    @State private var saving = false
    @State private var error: String?
    init(note:ARNote,save:@escaping (ARNote) async throws -> Void) {
        _note = State(initialValue:note); initial = note; self.save = save
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Title",text:Binding(get:{ note.title ?? "" },set:{ note.title = $0 }))
                TextEditor(text:$note.text).frame(minHeight:160).accessibilityLabel("Description")
            }
            .navigationTitle("Edit note")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement:.confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task { @MainActor in
                            defer { saving = false }
                            do { try await save(note); dismiss() } catch { self.error = error.localizedDescription }
                        }
                    }.disabled(saving || (note.title?.count ?? 0) > 200 || note.text.count > 16_000)
                }
            }
        }
        .frame(minWidth:280,minHeight:280)
        .interactiveDismissDisabled(saving || note != initial)
        .alert("Notes not saved",isPresented:Binding(get:{ error != nil },set:{ if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

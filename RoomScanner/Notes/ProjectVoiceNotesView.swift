import SwiftUI

/// Independent project evidence; never configures an ARSession or rewrites a scan.
struct ProjectVoiceNotesView: View {
    let projectID: UUID
    var initialReference: ProjectReference? = nil
    var onClose: (() -> Void)? = nil
    @Environment(RenovationWorkspace.self) private var workspace
    @State private var notes: [ARNote] = []
    @State private var referenceID = ""
    @State private var busy = false
    @State private var visible = false
    @State private var error: String?
    @State private var deleting: ARNote?
    @State private var editing: ARNote?
    @State private var playback = NotePlayback()
    @State private var playingID: UUID?
    @State private var waveforms: [UUID:[Double]] = [:]
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
                if recorder.recording {
                    Text(Duration.seconds(recorder.elapsed).formatted(.time(pattern:.minuteSecond)))
                        .monospacedDigit().accessibilityLabel("Recording duration")
                    HStack {
                        Button(recorder.paused ? "Resume recording" : "Pause recording") {
                            if recorder.paused { recorder.resume() } else { recorder.pause() }
                        }
                        Button("Stop and save") { recorder.stop() }
                    }
                } else if failedClip != nil {
                    Button("Retry saving recording") { if let failedClip { saveClip(failedClip) } }.disabled(busy)
                } else {
                    Button(action: startRecording) {
                        Label("Record voice note",systemImage: "mic.fill").frame(maxWidth: .infinity,minHeight: 36)
                    }.dsProminentControl(recording:true)
                        .disabled(busy || recorder.preparing || !references.contains { $0.id == referenceID })
                }
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
                ForEach(notes) { note in
                    VStack(alignment:.leading,spacing:8) {
                        if note.audioFileName == nil { Text(note.title ?? note.stem).font(.headline) }
                        if !note.text.isEmpty { Text(note.text).textSelection(.enabled) }
                        Text(note.createdAt,format:.dateTime).font(.caption).foregroundStyle(.secondary)
                        if let duration = note.audioDuration {
                            DSInlineAudioRow(title:note.title ?? note.stem,
                                subtitle:workspace.entry(note.reference).map { workspace.title($0) } ?? note.reference.itemID.uuidString,
                                time:Duration.seconds(playingID == note.id ? playback.time : 0).formatted(.time(pattern:.minuteSecond))+" / "+Duration.seconds(duration).formatted(.time(pattern:.minuteSecond)),
                                playing:playingID == note.id && playback.playing,waveform:waveforms[note.id] ?? [],
                                progress:Binding(get:{ playingID == note.id && playback.duration > 0 ? playback.time/playback.duration : 0 },set:{ if playingID == note.id { playback.seek($0*playback.duration) } }),
                                toggle:{ play(note) }).disabled(busy || audioActive)
                        }
                        HStack {
                            Button("Edit") { editing = note }.disabled(busy || audioActive)
                            Button("Delete",role:.destructive) { deleting = note }.disabled(busy || audioActive)
                        }
                    }.padding(.vertical,4)
                }
            }
            Section("Export") {
                Toggle("Include voice audio in export",isOn:$includeAudio).disabled(busy)
                Button("Export voice notes ZIP") { exportNotes() }.disabled(busy || audioActive)
                if let exportURL { ShareLink(item:exportURL) }
            }
        }
        .navigationTitle("Voice notes")
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
        .sheet(item:$editing) { note in VoiceNoteEditor(note:note) { updated in try await saveEdit(updated,expected:note) } }
        .alert("Delete voice note?",isPresented:Binding(get:{ deleting != nil },set:{ if !$0 { deleting = nil } })) {
            Button("Delete",role:.destructive) { if let deleting { remove(deleting) }; deleting = nil }
            Button("Cancel",role:.cancel) { deleting = nil }
        }
        .alert("Error",isPresented:Binding(get:{ error != nil || playback.error != nil },set:{ if !$0 { error = nil; playback.error = nil } })) {
            Button("OK") { error = nil; playback.error = nil }
        } message: { Text(error ?? playback.error ?? "") }
        #if os(iOS)
        .navigationBarBackButtonHidden(audioActive || busy || (failedClip != nil && !staged))
        .interactiveDismissDisabled(audioActive || busy || (failedClip != nil && !staged))
        .onChange(of:recorder.error) { _,message in if let message { error = message; recorder.error = nil } }
        #endif
        .task(id:busy) {
            guard busy else { return }; try? await Task.sleep(for:.seconds(30))
            guard !Task.isCancelled,busy else { return }
            busy = false; error = AppLanguage.text("Operation timed out. Saved recovery copies are kept. Retry or close.")
        }
        .onChange(of:references.map(\.id)) { _,_ in
            if !references.contains(where:{ $0.id == referenceID }),references.count == 1 { referenceID = references[0].id }
        }
        .onDisappear {
            visible = false
            playback.stop()
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
        playback.stop()
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
        let root = workspace.notesRoot
        do {
            let index = try await Task.detached { try ARNoteStore.index(root:root,projectID:projectID) }.value
            guard !Task.isCancelled,visible,root == workspace.notesRoot else { return }
            notes = index.notes
            let recoveryRoot = try VoiceNoteRecovery.root()
            recoveryCount = try await Task.detached { try ARNoteStore.index(root:recoveryRoot,projectID:projectID).notes.count }.value
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func play(_ note: ARNote) {
        if playingID == note.id,playback.duration > 0 { playback.toggle(); return }
        let root = workspace.notesRoot; busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let data = try await Task.detached { try ARNoteStore.audio(for:note,root:root) }.value
                guard visible,root == workspace.notesRoot else { return }
                playback.load(data); playingID = note.id; playback.toggle()
                Task {
                    if let peaks = try? await AudioWaveformCache.shared.peaks(for:data),visible,playingID == note.id {
                        if waveforms.count >= 32,let old = waveforms.keys.first(where:{ $0 != note.id }) { waveforms.removeValue(forKey:old) }
                        waveforms[note.id] = peaks
                    }
                }
            } catch { self.error = error.localizedDescription }
        }
    }
    private func exportNotes() {
        let root = workspace.notesRoot,selected = references,audio = includeAudio
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("voice-notes-"+UUID().uuidString+".zip")
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                try await Task.detached { try VoiceNotesExporter.export(root:root,projectID:projectID,references:selected,includeAudio:audio,to:target) }.value
                guard visible,root == workspace.notesRoot else { try? FileManager.default.removeItem(at:target); return }
                exportURL = target
            } catch { self.error = error.localizedDescription }
        }
    }
    private func recoverRecordings() {
        let root = workspace.notesRoot,selected = references; busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                try await Task.detached { try VoiceNoteRecovery.recover(projectID:projectID,from:VoiceNoteRecovery.root(),to:root,references:selected) }.value
                #if os(iOS)
                failedClip = nil; pendingID = nil; staged = false
                #endif
                await reload()
            } catch { self.error = error.localizedDescription }
        }
    }
    @MainActor private func saveEdit(_ note:ARNote,expected:ARNote) async throws {
        guard note.projectID == projectID else { throw CocoaError(.fileWriteNoPermission) }
        let root = workspace.notesRoot
        var updated = note; updated.modifiedAt = Date()
        do {
            _ = try await Task.detached { try ARNoteStore.upsertText(updated,root:root,expected:expected) }.value
            await reload()
        } catch { await reload(); throw error }
    }
    private func remove(_ note: ARNote) { playback.stop(); mutate { $0.notes.removeAll { $0.id == note.id } } }
    private func mutate(_ edit: @escaping (inout ARNoteIndex) throws -> Void) {
        let root = workspace.notesRoot; busy = true
        Task { @MainActor in
            defer { busy = false }
            do { _ = try await Task.detached { try ARNoteStore.update(root:root,projectID:projectID,edit:edit) }.value; await reload() }
            catch { self.error = error.localizedDescription }
        }
    }
    #if os(iOS)
    private func startRecording() {
        guard let reference = references.first(where:{ $0.id == referenceID }) else { return }
        playback.stop(); clipReference = reference; clipRoot = workspace.notesRoot
        pendingID = nil; staged = false
        recorder.onClip = { clip in saveClip(clip) }
        Task { guard visible else { return }; await recorder.start() }
    }
    private func saveClip(_ clip: NoteAudioRecorder.Clip) {
        guard !busy,let reference = clipReference,let root = clipRoot else { failedClip = clip; return }
        let id = pendingID ?? UUID(); pendingID = id
        busy = true; failedClip = clip
        Task { @MainActor in
            defer { busy = false }
            do {
                try await Task.detached {
                    var note = ARNote(id:id,projectID:projectID,reference:reference,number:1,level:nil,roomID:reference.itemID,position:nil,planPosition:nil,language:Locale.current.identifier)
                    note.audioFileName = note.stem+".m4a"; note.audioDuration = clip.duration; note.partial = clip.partial
                    try VoiceNoteRecovery.stage(note,audio:clip.data,at:VoiceNoteRecovery.root())
                }.value
                staged = true
                try await Task.detached { try VoiceNoteRecovery.recover(projectID:projectID,from:VoiceNoteRecovery.root(),to:root,references:[reference]) }.value
                failedClip = nil; pendingID = nil; staged = false; await reload()
            } catch { self.error = error.localizedDescription }
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

private struct VoiceNoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var note: ARNote
    var save: (ARNote) async throws -> Void
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("Title",text:Binding(get:{ note.title ?? "" },set:{ note.title = $0 }))
                TextEditor(text:$note.text).frame(minHeight:160).accessibilityLabel("Description")
            }
            .navigationTitle("Edit voice note")
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
        .interactiveDismissDisabled(saving)
        .alert("Notes not saved",isPresented:Binding(get:{ error != nil },set:{ if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

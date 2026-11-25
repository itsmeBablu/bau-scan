import SwiftUI

/// Independent project evidence; never configures an ARSession or rewrites a scan.
struct ProjectVoiceNotesView: View {
    let projectID: UUID
    @Environment(RenovationWorkspace.self) private var workspace
    @State private var notes: [ARNote] = []
    @State private var referenceID = ""
    @State private var busy = false
    @State private var visible = false
    @State private var error: String?
    @State private var deleting: ARNote?
    @State private var editing: ARNote?
    @State private var playback = NotePlayback()
    @State private var includeAudio = false
    @State private var exportURL: URL?
    @State private var recoveryCount = 0
    #if os(iOS)
    @State private var recorder = NoteAudioRecorder()
    @State private var consent = false
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
                Picker("Associated scan",selection:$referenceID) {
                    Text("None").tag("")
                    ForEach(references) { reference in
                        Text(workspace.entry(reference).map { workspace.title($0) } ?? reference.itemID.uuidString).tag(reference.id)
                    }
                }.disabled(busy || audioActive)
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
                    Button("Record voice note",systemImage:"mic.fill") { consent = true }
                        .disabled(busy || recorder.preparing || !references.contains { $0.id == referenceID })
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
                        Text(note.title ?? note.stem).font(.headline)
                        if !note.text.isEmpty { Text(note.text).textSelection(.enabled) }
                        Text(note.createdAt,format:.dateTime).font(.caption).foregroundStyle(.secondary)
                        if let duration = note.audioDuration {
                            Text(Duration.seconds(duration).formatted(.time(pattern:.minuteSecond))).monospacedDigit()
                            Button("Play recording",systemImage:"play.fill") { play(note) }.disabled(busy || audioActive)
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
            if playback.duration > 0 {
                Section("Playback") {
                    Button(playback.playing ? "Pause playback" : "Resume playback") { playback.toggle() }
                    Slider(value:Binding(get:{ playback.time },set:{ playback.seek($0) }),in:0...max(0.1,playback.duration))
                        .accessibilityLabel("Playback position")
                    Text(Duration.seconds(playback.time).formatted(.time(pattern:.minuteSecond))).monospacedDigit()
                }
            }
        }
        .navigationTitle("Voice notes")
        .task(id:projectID.uuidString+workspace.notesRoot.absoluteString) { visible = true; await reload() }
        .sheet(item:$editing) { note in VoiceNoteEditor(note:note) { updated in saveEdit(updated) } }
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
        .confirmationDialog("Record a local voice note?",isPresented:$consent,titleVisibility:.visible) {
            Button("Record voice note") { startRecording() }
            Button("Cancel",role:.cancel) {}
        } message: { Text("Microphone access is requested only for recording. No transcription or external upload is enabled.") }
        .onChange(of:recorder.error) { _,message in if let message { error = message; recorder.error = nil } }
        #endif
        .onDisappear {
            visible = false
            playback.stop()
            #if os(iOS)
            recorder.stop(partial:true); recorder.onClip = nil
            #endif
        }
    }
    private var audioActive: Bool {
        #if os(iOS)
        recorder.recording || recorder.preparing
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
        let root = workspace.notesRoot; busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let data = try await Task.detached { try ARNoteStore.read(root:root,projectID:projectID).audio[note.id] }.value
                guard visible,root == workspace.notesRoot else { return }
                guard let data else { throw CocoaError(.fileNoSuchFile) }
                playback.load(data); playback.toggle()
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
    private func saveEdit(_ note: ARNote) { mutate { index in
        guard let i = index.notes.firstIndex(where:{ $0.id == note.id }) else { throw CocoaError(.fileNoSuchFile) }
        index.notes[i].title = note.title; index.notes[i].text = note.text
    } }
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
        Task { await recorder.start() }
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

private struct VoiceNoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var note: ARNote
    var save: (ARNote) -> Void
    var body: some View {
        NavigationStack {
            Form {
                TextField("Title",text:Binding(get:{ note.title ?? "" },set:{ note.title = $0 }))
                TextEditor(text:$note.text).frame(minHeight:160).accessibilityLabel("Description")
            }
            .navigationTitle("Edit voice note")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("Save") { save(note); dismiss() }.disabled((note.title?.count ?? 0) > 200 || note.text.count > 16_000) }
            }
        }
        .frame(minWidth:280,minHeight:280)
    }
}

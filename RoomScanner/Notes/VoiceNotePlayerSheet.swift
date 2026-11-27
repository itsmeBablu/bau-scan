import SwiftUI

/// Text editing and optional audio replacement over the existing durable outbox.
struct VoiceNotePlayerSheet:View {
    let note:ARNote
    var root:URL = ScanVoiceNoteLibrary.root
    var displayTitle:String? = nil
    var onSave:(ARNote)->Void = { _ in }
    @State private var current:ARNote?
    @State private var textBaseline:ARNote?
    @State private var text = ""
    @State private var title = ""
    @State private var saving = false
    @State private var loading = true
    @State private var confirmingClose = false
    #if os(iOS)
    @State private var recorder = NoteAudioRecorder()
    @State private var pendingClip:NoteAudioRecorder.Clip?
    @State private var pendingRevision:ARNote?
    #endif
    @State private var error:String?
    @Environment(\.dismiss) private var dismiss
    private var baseline:ARNote { current ?? note }
    private var dirty:Bool { text != (textBaseline ?? note).text || title != ((textBaseline ?? note).title ?? "") }
    private var recordingActive:Bool {
        #if os(iOS)
        recorder.recording || recorder.preparing
        #else
        false
        #endif
    }
    private var pending:Bool {
        #if os(iOS)
        pendingClip != nil
        #else
        false
        #endif
    }
    var body:some View {
        NavigationStack {
            Form {
                Section("Written note") {
                    TextField("Title",text:$title)
                    TextField("Write a note",text:$text,axis:.vertical).lineLimit(3...10)
                    Button("Save text") { saveText() }.disabled(saving || loading || !dirty || text.count > 16_000 || title.count > 200)
                }.disabled(loading)
                if baseline.audioFileName != nil {
                    Section("Playback") { InlineVoiceNoteRow(note:baseline,root:root,subtitle:baseline.createdAt.formatted(),displayTitle:displayTitle,enabled:!saving && !recordingActive && !loading) }
                }
                #if os(iOS)
                Section("Voice note") {
                    if pendingClip != nil {
                        Button("Retry saving recording") { if let pendingClip { saveAudio(pendingClip) } }.disabled(saving)
                        Text("The previous recording stays available until its replacement is saved.").font(.caption)
                        Button("Discard unsaved recording",role:.destructive) { pendingClip = nil; pendingRevision = nil }
                            .disabled(saving)
                    } else {
                        Button(recorder.recording ? "Stop and save recording" : baseline.audioFileName == nil ? "Record voice note" : "Re-record") {
                            if recorder.recording { recorder.stop() }
                            else { NotePlayback.stopActive(); Task { await recorder.start() } }
                        }.dsProminentControl(recording:true).disabled(saving || loading || recorder.preparing)
                    }
                    if recorder.recording {
                        Text(Duration.seconds(recorder.elapsed).formatted(.time(pattern:.minuteSecond))).monospacedDigit()
                        Button("Discard unsaved recording",role:.destructive) { recorder.stop(cancel:true,reason:"Recording discarded") }
                    }
                    if let message = recorder.error { Text(message).font(.caption) }
                }
                #endif
                if saving { ProgressView("Saving voice note") }
                if let error { Text(error).font(.caption).foregroundStyle(DS.ColorToken.error.color) }
            }.navigationTitle(displayTitle ?? (baseline.audioFileName == nil ? AppLanguage.text("Written note") : AppLanguage.text("Voice note")))
                .toolbar { ToolbarItem(placement:.confirmationAction) {
                    Button("Done") { if dirty || recordingActive || pending { confirmingClose = true } else { dismiss() } }.disabled(saving)
                } }
        }.task(id:note.id) {
            loading = true
            current = note; textBaseline = note; text = note.text; title = note.title ?? ""
            #if os(iOS)
            recorder.onClip = { clip in saveAudio(clip) }
            #endif
            do {
                let root = root, projectID = note.projectID
                let index = try await BackgroundWork.run { try ARNoteStore.index(root:root,projectID:projectID) }
                guard !Task.isCancelled else { return }
                if let latest = index.notes.first(where:{ $0.id == note.id }),latest.reference == note.reference {
                    current = latest; textBaseline = latest; text = latest.text; title = latest.title ?? ""
                } else { throw CocoaError(.fileNoSuchFile) }
                loading = false
            } catch {
                guard !Task.isCancelled else { return }
                loading = false; self.error = error.localizedDescription
            }
        }
        .interactiveDismissDisabled(saving || recordingActive || pending || dirty)
        .confirmationDialog("Close note with unsaved changes?",isPresented:$confirmingClose,titleVisibility:.visible) {
            if dirty && !recordingActive && !pending { Button("Save and close") { saveText(close:true) } }
            Button("Keep editing",role:.cancel) {}
            if !recordingActive && !pending { Button("Discard unsaved edits",role:.destructive) { dismiss() } }
        } message: { Text("Save or discard text changes before closing. Stop the active recording and retry any failed save first.") }
        .onDisappear {
            #if os(iOS)
            recorder.stop(partial:true)
            #endif
        }
        #if os(iOS)
        .presentationDetents([.medium,.large]).presentationDragIndicator(.visible)
        #endif
    }
    private func saveText(close:Bool = false) {
        guard !saving else { return }; saving = true
        var value = baseline; value.text = text; value.title = title; value.modifiedAt = Date()
        let expected = textBaseline ?? note
        Task { @MainActor in
            defer { saving = false }
            do {
                let saved = try await NoteSaveWorker.text(value,expected:expected,root:root)
                current = saved; textBaseline = saved; onSave(saved); error = nil
                if close { dismiss() }
            } catch { self.error = error.localizedDescription }
        }
    }
    #if os(iOS)
    private func saveAudio(_ clip:NoteAudioRecorder.Clip) {
        guard !saving else { pendingClip = clip; return }
        saving = true; pendingClip = clip
        if pendingRevision == nil {
            var value = baseline
            value.audioModifiedAt = Date()
            value.audioFileName = value.stem+".m4a"; value.audioDuration = clip.duration; value.partial = clip.partial
            pendingRevision = value
        }
        guard let value = pendingRevision else { saving = false; return }
        Task { @MainActor in
            defer { saving = false }
            do {
                let saved = try await NoteSaveWorker.audioRevision(value,audio:clip.data,root:root,outbox:VoiceNoteRecovery.root())
                // Audio replacement must not silently save an unsaved text draft.
                current = saved; onSave(saved); pendingClip = nil; pendingRevision = nil; error = nil
            } catch { self.error = error.localizedDescription }
        }
    }
    #endif
}

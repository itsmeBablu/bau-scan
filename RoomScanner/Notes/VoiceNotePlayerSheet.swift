import SwiftUI

struct VoiceNotePlayerSheet:View {
    let note:ARNote
    var root:URL = ScanVoiceNoteLibrary.root
    var onSave:(ARNote)->Void = { _ in }
    @State private var current:ARNote?
    @State private var text = ""
    @State private var saving = false
    #if os(iOS)
    @State private var recorder = NoteAudioRecorder()
    #endif
    @State private var player = NotePlayback()
    @State private var error:String?
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        NavigationStack {
            VStack(spacing:16) {
                Image(systemName:"mic.circle.fill").font(.largeTitle).foregroundStyle(DS.ColorToken.info.color)
                Text(note.title ?? "Pinned note").font(.headline)
                TextField("Write a note",text:$text,axis:.vertical).textFieldStyle(.roundedBorder).lineLimit(2...5)
                Button("Save text") { saveText() }.disabled(saving)
                #if os(iOS)
                Button(recorder.recording ? "Stop and save recording" : "Record voice note") {
                    if recorder.recording { recorder.stop() }
                    else { player.stop(); Task { await recorder.start() } }
                }.buttonStyle(.bordered).dsRecordingTint().disabled(saving || recorder.preparing)
                if recorder.recording { Text(Duration.seconds(recorder.elapsed).formatted(.time(pattern:.minuteSecond))).monospacedDigit() }
                if let message = recorder.error { Text(message).font(.caption) }
                #endif
                if player.duration > 0 {
                    Button(player.playing ? "Pause playback" : "Resume playback") { player.toggle() }.dsProminentControl()
                    Slider(value:Binding(get:{ player.time },set:{ player.seek($0) }),in:0...max(0.1,player.duration)).accessibilityLabel("Playback position")
                    Text(Duration.seconds(player.time).formatted(.time(pattern:.minuteSecond))).monospacedDigit()
                }
                if let error { Text(error).font(.caption) }
                Spacer()
            }.padding().navigationTitle("Voice note")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
        }.task(id:note.id) {
            current = note; text = note.text
            #if os(iOS)
            recorder.onClip = { clip in saveAudio(clip) }
            #endif
            do {
                let library = try await Task.detached { try ARNoteStore.read(root:root,projectID:note.projectID) }.value
                if let latest = library.index.notes.first(where:{ $0.id == note.id }) { current = latest; text = latest.text }
                if let data = library.audio[note.id] { player.load(data) }
            } catch { self.error = error.localizedDescription }
        }.onDisappear {
            player.stop()
            #if os(iOS)
            recorder.stop(partial:true)
            #endif
        }
        #if os(iOS)
        .presentationDetents([.medium,.large]).presentationDragIndicator(.visible)
        #endif
    }
    private func saveText() {
        guard !saving else { return }; saving = true
        var value = current ?? note; value.text = text; value.modifiedAt = Date()
        let expected = current ?? note
        Task { @MainActor in
            defer { saving = false }
            do {
                let saved = try await Task.detached { try ARNoteStore.upsertText(value,root:root,expected:expected) }.value
                current = saved; onSave(saved); error = nil
            } catch { self.error = error.localizedDescription }
        }
    }
    #if os(iOS)
    private func saveAudio(_ clip:NoteAudioRecorder.Clip) {
        saving = true
        var value = current ?? note; value.text = text; value.modifiedAt = Date()
        value.audioModifiedAt = value.modifiedAt
        value.audioFileName = value.stem+".m4a"; value.audioDuration = clip.duration; value.partial = clip.partial
        Task { @MainActor in
            defer { saving = false }
            do {
                let saved = try await Task.detached {
                    try VoiceNoteRecovery.publishRevision(value,audio:clip.data,to:root,outbox:VoiceNoteRecovery.root())
                }.value
                current = saved; onSave(saved); player.load(clip.data); error = nil
            } catch { self.error = error.localizedDescription }
        }
    }
    #endif

}

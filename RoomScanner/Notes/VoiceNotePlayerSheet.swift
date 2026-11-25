import SwiftUI

struct VoiceNotePlayerSheet:View {
    let note:ARNote
    var root:URL = ScanVoiceNoteLibrary.root
    @State private var player = NotePlayback()
    @State private var error:String?
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        NavigationStack {
            VStack(spacing:16) {
                Image(systemName:"mic.circle.fill").font(.largeTitle).foregroundStyle(.purple)
                Text(note.title ?? note.text).font(.headline)
                if player.duration > 0 {
                    Button(player.playing ? "Pause playback" : "Resume playback") { player.toggle() }.buttonStyle(.borderedProminent)
                    Slider(value:Binding(get:{ player.time },set:{ player.seek($0) }),in:0...max(0.1,player.duration)).accessibilityLabel("Playback position")
                    Text(Duration.seconds(player.time).formatted(.time(pattern:.minuteSecond))).monospacedDigit()
                }
                if let error { Text(error).font(.caption) }
                Spacer()
            }.padding().navigationTitle("Voice note")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
        }.task(id:note.id) {
            do {
                let library = try await Task.detached { try ARNoteStore.read(root:root,projectID:note.projectID) }.value
                if let data = library.audio[note.id] { player.load(data) }
            } catch { self.error = error.localizedDescription }
        }.onDisappear { player.stop() }
        #if os(iOS)
        .presentationDetents([.medium,.large]).presentationDragIndicator(.visible)
        #endif
    }
}

import SwiftUI

/// Shared by the voice library and dashboard; one validated clip is read on demand.
struct InlineVoiceNoteRow: View {
    let note:ARNote
    let root:URL
    let subtitle:String
    var enabled = true
    @State private var playback = NotePlayback()
    @State private var waveform:[Double] = []
    @State private var loading = false
    @State private var active = false
    @State private var request = UUID()
    @State private var message:String?
    var body:some View {
        DSInlineAudioRow(title:note.title ?? note.stem,subtitle:subtitle,
            time:Duration.seconds(playback.time).formatted(.time(pattern:.minuteSecond))+" / "+Duration.seconds(note.audioDuration ?? 0).formatted(.time(pattern:.minuteSecond)),
            playing:playback.playing,waveform:waveform,
            progress:Binding(get:{ playback.duration > 0 ? playback.time/playback.duration : 0 },set:{ playback.seek($0*playback.duration) }),toggle:toggle)
            .disabled(!enabled || loading)
            .overlay(alignment:.trailing) { if loading { ProgressView() } }
            .onAppear { active = true }
            .onDisappear { active = false; reset() }
            .onChange(of:root) { _,_ in reset() }
            .onChange(of:note.audioModifiedAt) { _,_ in reset() }
            .onChange(of:enabled) { _,value in if !value { reset() } }
            .alert("Error",isPresented:Binding(get:{ message != nil || playback.error != nil },set:{ if !$0 { message = nil; playback.error = nil } })) {
                Button("OK") { message = nil; playback.error = nil }
            } message: { Text(message ?? playback.error ?? "") }
    }
    private func reset() { request = UUID(); playback.stop(); loading = false; waveform = [] }
    private func toggle() {
        guard enabled,!loading else { return }
        if playback.duration > 0 { playback.toggle(); return }
        loading = true
        let token = UUID(),intent = NotePlayback.reserveRequest(),note = note,root = root
        request = token
        Task {
            do {
                let data = try await Task.detached(priority:.userInitiated) { try ARNoteStore.audio(for:note,root:root) }.value
                guard active,request == token,enabled else { return }
                guard NotePlayback.isCurrentRequest(intent) else { loading = false; return }
                playback.load(data); playback.toggle(); loading = false
                if let peaks = try? await AudioWaveformCache.shared.peaks(for:data),active,request == token { waveform = peaks }
            } catch {
                guard active,request == token else { return }; loading = false; message = error.localizedDescription
            }
        }
    }
}

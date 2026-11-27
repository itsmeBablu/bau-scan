import SwiftUI

/// Shared by the voice library and dashboard; one validated clip is read on demand.
struct InlineVoiceNoteRow: View {
    let note:ARNote
    let root:URL
    let subtitle:String
    var displayTitle:String? = nil
    var enabled = true
    @State private var playback = NotePlayback()
    @State private var waveform:[Double] = []
    @State private var loading = false
    @State private var active = false
    @State private var request = UUID()
    @State private var message:String?
    @State private var desiredProgress = 0.0
    var body:some View {
        DSInlineAudioRow(title:note.title.flatMap { $0.isEmpty ? nil : $0 } ?? displayTitle ?? note.stem,subtitle:subtitle,
            time:Duration.seconds(playback.duration > 0 ? playback.time : desiredProgress*(note.audioDuration ?? 0)).formatted(.time(pattern:.minuteSecond))+" / "+Duration.seconds(note.audioDuration ?? 0).formatted(.time(pattern:.minuteSecond)),
            playing:playback.playing,waveform:waveform,
            progress:Binding(get:{ playback.duration > 0 ? playback.time/playback.duration : desiredProgress },set:{ value in
                desiredProgress = min(1,max(0,value))
                if playback.duration > 0 { playback.seek(desiredProgress*playback.duration) }
                else if !loading { load(startPlaying:false) }
            }),toggle:toggle)
            .disabled(!enabled)
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
    private func reset() { request = UUID(); playback.stop(); loading = false; waveform = []; desiredProgress = 0 }
    private func toggle() {
        guard enabled,!loading else { return }
        if playback.duration > 0 { playback.toggle(); return }
        load(startPlaying:true)
    }
    private func load(startPlaying:Bool) {
        loading = true
        let token = UUID(),intent = NotePlayback.reserveRequest(),note = note,root = root
        request = token
        Task {
            do {
                let data = try await BackgroundWork.run { try ARNoteStore.audio(for:note,root:root) }
                guard active,request == token,enabled else { return }
                guard NotePlayback.isCurrentRequest(intent) else { loading = false; return }
                playback.load(data); playback.seek(desiredProgress*playback.duration)
                if startPlaying { playback.toggle() }; loading = false
                if let peaks = try? await AudioWaveformCache.shared.peaks(for:data),active,request == token { waveform = peaks }
            } catch {
                guard active,request == token else { return }; loading = false; message = error.localizedDescription
            }
        }
    }
}

import AVFoundation
import Observation

@MainActor @Observable final class NotePlayback {
    private static weak var active: NotePlayback?
    private(set) var playing = false
    private(set) var time = 0.0
    private(set) var duration = 0.0
    var speed: Float = 1 { didSet { player?.rate = speed } }
    var error: String?
    private var player: AVAudioPlayer?
    private var tick: Task<Void,Never>?
    #if os(iOS)
    private var category: AVAudioSession.Category?
    private var mode: AVAudioSession.Mode?
    private var options: AVAudioSession.CategoryOptions?
    #endif
    func load(_ data: Data) {
        stop()
        do { let player = try AVAudioPlayer(data:data); player.enableRate = true; player.rate = speed; self.player = player; duration = player.duration }
        catch { self.error = error.localizedDescription }
    }
    func toggle() {
        guard let player else { return }
        if playing { player.pause(); playing = false; releaseAudio(); return }
        do {
            if let other = Self.active,other !== self { other.stop() }
            Self.active = self
            #if os(iOS)
            let audio = AVAudioSession.sharedInstance()
            category = audio.category; mode = audio.mode; options = audio.categoryOptions
            try audio.setCategory(.playback,mode:.default,options:.mixWithOthers); try audio.setActive(true)
            #endif
            if player.currentTime >= duration { player.currentTime = 0 }
            playing = player.play(); if !playing { releaseAudio(); return }
            tick?.cancel()
            tick = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for:.milliseconds(150))
                    guard let self,!Task.isCancelled,let player = self.player else { return }
                    self.time = player.currentTime
                    if !player.isPlaying { self.playing = false; self.releaseAudio(); return }
                }
            }
        } catch { self.error = error.localizedDescription; releaseAudio() }
    }
    func seek(_ time: Double) { self.time = min(duration,max(0,time)); player?.currentTime = self.time }
    func stop() {
        tick?.cancel(); tick = nil; player?.stop(); player = nil; playing = false; time = 0; duration = 0; releaseAudio()
        if Self.active === self { Self.active = nil }
    }
    private func releaseAudio() {
        #if os(iOS)
        if let category,let mode,let options {
            do { try AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation); try AVAudioSession.sharedInstance().setCategory(category,mode:mode,options:options) }
            catch { self.error = error.localizedDescription }
        }
        category = nil; mode = nil; options = nil
        #endif
    }
}


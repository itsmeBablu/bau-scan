#if os(iOS)
import AVFoundation

/// Configure the shared audio route before RoomPlan starts, never during a held
/// recording. The recorder borrows it; only capture dismissal restores it.
@MainActor enum CaptureAudioSession {
    private static var owners:Set<UUID> = []
    private static var previous:(AVAudioSession.Category,AVAudioSession.Mode,AVAudioSession.CategoryOptions)?
    static var active:Bool { !owners.isEmpty }
    static func acquire(_ id:UUID) throws {
        guard !owners.contains(id) else { return }
        if owners.isEmpty {
            let session = AVAudioSession.sharedInstance()
            let original = (session.category,session.mode,session.categoryOptions)
            do {
                try session.setCategory(.playAndRecord,mode:.videoRecording,options:[.mixWithOthers,.defaultToSpeaker,.allowBluetoothHFP])
                try session.setActive(true)
                previous = original
            } catch {
                try? session.setCategory(original.0,mode:original.1,options:original.2)
                throw error
            }
        }
        owners.insert(id)
    }
    static func release(_ id:UUID) {
        guard owners.remove(id) != nil,owners.isEmpty,let previous else { return }
        self.previous = nil
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false,options:.notifyOthersOnDeactivation)
            try session.setCategory(previous.0,mode:previous.1,options:previous.2)
        } catch { UserDefaults.standard.set((error as NSError).code,forKey:"voice.captureAudioRestoreError") }
    }
}
#endif

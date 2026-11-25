#if os(iOS)
import AVFoundation
import Observation
import UIKit
import OSLog

/// Owns audio only. Has no ARKit imports and never configures camera capture.
@MainActor @Observable final class NoteAudioRecorder: NSObject, AVAudioRecorderDelegate {
    struct Clip { var data: Data; var duration: Double; var partial: Bool }
    private(set) var recording = false
    private(set) var paused = false
    private(set) var preparing = false
    private(set) var elapsed = 0.0
    private(set) var levels: [Double] = []
    private(set) var completed = 0
    var error: String?
    var onClip: ((Clip) -> Void)?
    private var recorder: AVAudioRecorder?
    private let lifecycle = AudioRecorderLifecycle()
    private var timer: Task<Void,Never>? {
        get { lifecycle.timer }
        set { lifecycle.timer = newValue }
    }
    private var machine = RecorderStateMachine()
    private var activatedAt = Date.distantPast
    private var preparationTimeout: Task<Void,Never>?
    private var previousCategory: AVAudioSession.Category?
    private var previousMode = AVAudioSession.Mode.default
    private var previousOptions = AVAudioSession.CategoryOptions()
    private var ownedURL: URL?
    private static let log = Logger(subsystem:Bundle.main.bundleIdentifier ?? "dWalkScan",category:"voice")
    private static weak var owner: NoteAudioRecorder?
    override init() {
        super.init()
        for name in [AVAudioSession.interruptionNotification,AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereResetNotification,UIApplication.didEnterBackgroundNotification] {
            lifecycle.observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] notification in
                Task { @MainActor in self?.handle(notification) }
            })
        }
    }
    func start() async {
        guard !recording,!preparing else { return }
        guard Self.owner == nil || Self.owner === self else { error = AppLanguage.text("Another voice note is recording. Stop it before starting a new one."); return }
        Self.owner = self
        preparing = true; let request = machine.prepare()
        Self.log.info("start permission=\(AVAudioApplication.shared.recordPermission.rawValue,privacy:.public)")
        preparationTimeout?.cancel()
        preparationTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for:.seconds(15))
            guard !Task.isCancelled,let self,self.preparing,self.machine.generation == request else { return }
            self.stop(cancel:true,reason:"Recording preparation timed out")
        }
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard request == machine.generation else { return }
        guard allowed else { preparing = false; Self.owner = nil; error = AppLanguage.text("Microphone access is required. Open Settings to allow it."); return }
        do {
            let root = FileManager.default.temporaryDirectory
            let values = try root.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey])
            if let available = values.volumeAvailableCapacityForImportantUsage,available < 20*1_048_576 { throw CocoaError(.fileWriteOutOfSpace) }
            let url = root.appendingPathComponent("note-recording-"+UUID().uuidString).appendingPathExtension("m4a")
            let audio = AVAudioSession.sharedInstance()
            previousCategory = audio.category; previousMode = audio.mode; previousOptions = audio.categoryOptions
            Self.log.info("Voice note: switching audio category from \(audio.category.rawValue,privacy:.public) to playAndRecord; meter interval 100 ms")
            activatedAt = Date()
            if ![AVAudioSession.Category.playAndRecord,.record,.multiRoute].contains(audio.category) {
                try audio.setCategory(.playAndRecord,mode:.default,options:[.mixWithOthers,.defaultToSpeaker,.allowBluetoothHFP])
            }
            try audio.setActive(true)
            activatedAt = Date()
            let recorder = try AVAudioRecorder(url:url,settings:[AVFormatIDKey:kAudioFormatMPEG4AAC,
                AVSampleRateKey:22_050,AVNumberOfChannelsKey:1,AVEncoderBitRateKey:32_000])
            self.recorder = recorder; ownedURL = url; recorder.delegate = self; recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(),recorder.record(forDuration:60) else { throw CocoaError(.fileWriteUnknown) }
            guard machine.started(request) else { recorder.stop(); cleanup(); return }
            preparationTimeout?.cancel()
            elapsed = 0; levels = []; recording = true; paused = false; preparing = false; error = nil
            timer = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for:.milliseconds(100))
                    guard !Task.isCancelled,let self,self.recording,let recorder = self.recorder else { return }
                    self.elapsed = min(60,recorder.currentTime); recorder.updateMeters()
                    self.levels.append(pow(10,Double(recorder.averagePower(forChannel:0))/20))
                    if self.levels.count > 32 { self.levels.removeFirst() }
                    if AVAudioApplication.shared.recordPermission != .granted { self.stop(partial:true); return }
                    if Int(self.elapsed*10).isMultiple(of:10) {
                        let free = try? root.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
                        if let free,free < 5*1_048_576 { self.stop(partial:true); return }
                    }
                    if self.elapsed >= 59.9 { self.stop(); return }
                }
            }
        } catch { preparing = false; self.error = error.localizedDescription; cleanup() }
    }
    func stop(cancel: Bool = false,partial: Bool = false,reason:String = "User stopped recording") {
        machine.stop(); preparationTimeout?.cancel(); preparing = false
        UserDefaults.standard.set(reason,forKey:"voice.lastStopReason")
        Self.log.info("stop reason=\(reason,privacy:.public) permission=\(AVAudioApplication.shared.recordPermission.rawValue,privacy:.public)")
        if partial || reason == "Recording preparation timed out" { error = AppLanguage.text(reason) }
        guard let recorder else { if Self.owner === self { Self.owner = nil }; return }
        let duration = max(elapsed,recorder.currentTime)
        self.recorder = nil; recording = false; timer?.cancel(); timer = nil
        recorder.stop(); paused = false
        defer { cleanup() }
        guard NoteRecordingPolicy.action(seconds:duration,cancelled:cancel),let url = ownedURL else {
            error = AppLanguage.text(cancel ? "Recording discarded" : "Recording too short. Hold the microphone for at least half a second.")
            return
        }
        do {
            let file = try AVAudioFile(forReading:url)
            let format = file.fileFormat
            let actualDuration = Double(file.length)/file.processingFormat.sampleRate
            let data = try Data(contentsOf:url)
            guard format.channelCount == 1,(format.settings[AVFormatIDKey] as? NSNumber)?.uint32Value == kAudioFormatMPEG4AAC,
                  actualDuration.isFinite,actualDuration >= 0.5,actualDuration <= 60.1,
                  data.count <= ARNoteIndex.maximumClipBytes else { throw CocoaError(.fileReadCorruptFile) }
            completed += 1
            onClip?(.init(data:data,duration:min(60,actualDuration),partial:partial))
        } catch { self.error = error.localizedDescription }
    }
    private func handle(_ notification:Notification) {
        guard preparing || recording else { return }
        let event:RecorderEventPolicy.Event
        if notification.name == AVAudioSession.routeChangeNotification {
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
            let previous = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
            let inputs = Set(AVAudioSession.sharedInstance().currentRoute.inputs.map(\.uid))
            let lost = previous?.inputs.contains(where:{ !inputs.contains($0.uid) }) ?? inputs.isEmpty
            Self.log.info("route reason=\(reason ?? 0,privacy:.public) inputLost=\(lost,privacy:.public)")
            event = .route(reason,inputLost:lost)
        } else if notification.name == AVAudioSession.interruptionNotification {
            event = .interruption((notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue)
        } else { event = notification.name == UIApplication.didEnterBackgroundNotification ? .background : .mediaReset }
        if let reason = RecorderEventPolicy.stopReason(event,sinceActivation:Date().timeIntervalSince(activatedAt)) { stop(partial:true,reason:reason) }
    }
    private func cleanup() {
        preparationTimeout?.cancel()
        recorder?.stop(); recorder = nil; recording = false; timer?.cancel(); timer = nil
        if let ownedURL { try? FileManager.default.removeItem(at:ownedURL) }; ownedURL = nil
        if let previousCategory {
            let audio = AVAudioSession.sharedInstance()
            do {
                try audio.setActive(false,options:.notifyOthersOnDeactivation)
                Self.log.info("Voice note: restoring audio category \(previousCategory.rawValue,privacy:.public)")
                try audio.setCategory(previousCategory,mode:previousMode,options:previousOptions)
            } catch { self.error = error.localizedDescription }
        }
        previousCategory = nil
        if Self.owner === self { Self.owner = nil }
    }
    func pause() { guard recording,!paused else { return }; recorder?.pause(); paused = true }
    func resume() {
        guard recording,paused else { return }
        if recorder?.record() == true { paused = false }
        else { stop(partial:true); error = AppLanguage.text("Recording could not resume.") }
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder,successfully flag: Bool) {
        Task { @MainActor in guard self.recorder === recorder else { return }; self.stop(partial:!flag,reason:flag ? "Recording finished" : "Recording stopped by audio system") }
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder,error: Error?) {
        Task { @MainActor in guard self.recorder === recorder else { return }; self.stop(partial:true,reason:"Recording stopped by audio system") }
    }
}

/// The non-actor owner tears down observer tokens and the task without accessing
/// isolated recorder state from the recorder's nonisolated deinitializer.
private final class AudioRecorderLifecycle {
    var timer: Task<Void,Never>?
    var observers: [NSObjectProtocol] = []
    deinit {
        timer?.cancel()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}
#endif

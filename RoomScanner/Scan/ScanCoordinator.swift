#if canImport(RoomPlan)
import Foundation
import Observation
import ARKit
import RoomPlan
import AVFoundation

/// RoomPlan rooms share one ARSession. Completed rooms are stored before
/// continuing; the structure is built from disk when Finish is selected.
@Observable
@MainActor
final class ScanCoordinator {
    enum State: Equatable {
        case idle, scanning, processing, roomSaved
        case finished(ScanResult)
        /// House mode: alignment in progress.
        case merging
        case finishedHouse(HouseScanResult)
        case failed(AppError)
    }

    /// House result ready to be saved.
    struct HouseScanResult: Equatable {
        let structure: StructureInput
        let capturedStructureData: Data
        let usdzData: Data?
        /// Captures per room (key: room ID) — `room.json`, parametric USDZ, and mesh.
        let rooms: [UUID: RoomCapture]
        struct RoomCapture: Equatable { let capturedRoomData: Data; let usdzData: Data?; let usdzMeshData: Data? }
        static func == (a: HouseScanResult, b: HouseScanResult) -> Bool { a.structure.id == b.structure.id }
    }

    /// Result ready to be saved.
    struct ScanResult: Equatable {
        let scan: ScanInput
        let capturedRoomData: Data
        let usdzData: Data?
        let usdzMeshData: Data?
        static func == (a: ScanResult, b: ScanResult) -> Bool { a.scan.id == b.scan.id }
    }

    private(set) var state: State = .idle
    /// Prevents late camera-permission and processing callbacks from reviving a dismissed scan.
    private var active = false
    private(set) var cameraDiagnostic: String?
    private var cameraWatchdog: Task<Void,Never>?
    let mode: ScanMode
    static let radiatorPreferenceKey = "houseScan.detectRadiators"
    let detectsRadiators: Bool
    /// Rooms captured in house mode (shared world coordinate space).
    var persistence: CapturePersistence?
    private var pendingRoom: PersistedRoom?
    private var finishingHouse = false
    private var trackingStarted = false
    private let checkpointObserver = RoomCheckpointObserver()
    private var latestRoom: CapturedRoom?
    private var checkpointPolicy = ScanCheckpointPolicy()
    private var checkpointTask: Task<Void,Never>?
    private var checkpointTicker: Task<Void,Never>?
    private var lastSnapshotAttempt = -Double.infinity
    private(set) var thermalState = ProcessInfo.processInfo.thermalState.rawValue
    private(set) var residentBytes: UInt64 = 0
    let arSession: ARSession
    let captureView: RoomCaptureView
    /// `RoomCaptureViewDelegate` requires `NSCoding`: carried by dedicated helper object.
    private let delegateProxy = CaptureViewDelegateProxy()

    static var isSupported: Bool { RoomCaptureSession.isSupported }

    var prepareVoiceRecording = true
    private let audioOwner = UUID()

    init(mode: ScanMode = .room, arSession: ARSession = ARSession()) {
        self.mode = mode
        detectsRadiators = mode == .house &&
            (UserDefaults.standard.object(forKey: Self.radiatorPreferenceKey) as? Bool ?? true)
        // Preserve the explicit session ownership used by the stable pre-change capture flow.
        self.arSession = arSession
        self.captureView = RoomCaptureView(frame: .zero, arSession: arSession)
        delegateProxy.onResult = { [weak self] room, error in
            Task { @MainActor in self?.receive(room: room, error: error) }
        }
        captureView.delegate = delegateProxy
        checkpointObserver.onUpdate = { [weak self] room in Task { @MainActor in
            guard let self,self.state == .scanning else { return }; self.latestRoom = room; self.flushCheckpoint(.update)
        } }
    }

    /// Starts scan (requests camera permission if needed).
    func start() {
        guard !active else { return }
        active = true
        guard Self.isSupported else { active = false; state = .failed(.unsupportedDevice); return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            active = false
            state = .failed(.cameraDenied)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    guard self.active else { return }
                    if granted { self.prepareAudioThenRun() } else { self.active = false; self.state = .failed(.cameraDenied) }
                }
            }
        default:
            prepareAudioThenRun()
        }
    }

    private func prepareAudioThenRun() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let allowed = self.prepareVoiceRecording ? await AVAudioApplication.requestRecordPermission() : false
            guard self.active else { return }
            if allowed {
                do { try CaptureAudioSession.acquire(self.audioOwner) }
                catch { UserDefaults.standard.set((error as NSError).code,forKey:"voice.captureAudioPrepareError") }
            }
            self.run()
        }
    }

    private func run() {
        cameraDiagnostic = nil
        guard active else { return }
        if mode == .house && !trackingStarted {
            trackingStarted = true
            // Configure the shared session before RoomPlan starts. Never rerun it
            // from the passive radiator observer while RoomPlan is capturing.
            let tracking = ARWorldTrackingConfiguration()
            for semantic: ARConfiguration.FrameSemantics in [.sceneDepth,.smoothedSceneDepth] where ARWorldTrackingConfiguration.supportsFrameSemantics(semantic) {
                tracking.frameSemantics.insert(semantic)
            }
            arSession.run(tracking)
        }
        var config = RoomCaptureSession.Configuration()
        config.isCoachingEnabled = true
        state = .scanning
        if captureView.captureSession.delegate !== checkpointObserver {
            checkpointObserver.forward = captureView.captureSession.delegate
            captureView.captureSession.delegate = checkpointObserver
        }
        captureView.captureSession.run(configuration: config)
        checkpointTicker?.cancel()
        checkpointTicker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for:.seconds(1))
                guard !Task.isCancelled else { return }; self?.flushCheckpoint(.update)
            }
        }
        cameraWatchdog?.cancel()
        cameraWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for:.seconds(8))
            guard !Task.isCancelled,let self,self.active,self.state == .scanning,
                  self.arSession.currentFrame == nil else { return }
            self.cameraDiagnostic = "No camera frames received. Check camera access in Settings and close other camera views before reopening this scan."
        }
    }

    /// User completes room: RoomPlan post-processes and calls `didPresent`.
    /// In house mode, `ARSession` remains active for next room.
    func finish() {
        guard state == .scanning || state == .roomSaved else { return }
        finishingHouse = true
        if state == .roomSaved { state = .processing; finishHouse(); return }
        latestRoom = nil
        state = .processing
        if mode == .house { captureView.captureSession.stop(pauseARSession: false) } else { captureView.captureSession.stop() }
    }

    var liveLevel: Int? { latestRoom?.story }
    var liveRoomID: UUID? { latestRoom?.identifier }
    func notePose() -> [Double]? {
        guard let frame = arSession.currentFrame else { return nil }
        return (0..<4).flatMap { c in (0..<4).map { Double(frame.camera.transform[c][$0]) } }
    }
    func noteSurface() -> TechnicalPoint3? {
        guard let point = CaptureSurfacePoint.center(session:arSession) else { return nil }
        guard let latestRoom else { return point }
        let scan = CapturedRoomAdapter.scanInput(from:latestRoom)
        var builder = FloorPlanBuilder(); builder.alignToLongestWall = false
        let room = builder.build(from:scan,name:"")
        guard room.floorOutlineSource != .boundsEstimate else { return point }
        let floor = StoryDetector.floorHeight(of:scan)
        let local = TechnicalPoint3(x:point.x,y:point.y-floor,z:point.z)
        let anchored = ScanNoteRegistration.contained(local,in:room)
        return .init(x:anchored.x,y:anchored.y+floor,z:anchored.z)
    }
    func flushCheckpoint(_ trigger:ScanCheckpointPolicy.Trigger) {
        guard active,state == .scanning,checkpointTask == nil,let room = latestRoom,let persistence else { return }
        let time = Date().timeIntervalSinceReferenceDate
        let sample = ScanCheckpointPolicy.Sample(time:time,geometry:room.walls.count+room.objects.count,bytes:persistence.snapshotBytes)
        guard trigger != .update || time-lastSnapshotAttempt >= checkpointPolicy.minimumSpacing else { return }
        lastSnapshotAttempt = time
        thermalState = ProcessInfo.processInfo.thermalState.rawValue
        residentBytes = 0
        #if os(iOS)
        residentBytes = CaptureMemory.residentBytes()
        #endif
        checkpointTask = Task { @MainActor [weak self] in
            defer { self?.checkpointTask = nil }
            do {
                let value = try await Task.detached(priority:.utility) {
                    try PersistedRoom(scan:CapturedRoomAdapter.scanInput(from:room),raw:CapturedRoomAdapter.encode(room),partial:true)
                }.value
                let actual = ScanCheckpointPolicy.Sample(time:time,geometry:sample.geometry,bytes:value.raw.count)
                guard self?.checkpointPolicy.shouldSave(actual,trigger:trigger) == true else { return }
                try await persistence.room(value)
                self?.checkpointPolicy.committed(.init(time:time,geometry:sample.geometry,bytes:value.raw.count))
            } catch { /* CapturePersistence exposes the failed write; never discard the draft. */ }
        }
    }
    func flushAndPause(_ trigger:ScanCheckpointPolicy.Trigger) async {
        await checkpointTask?.value; flushCheckpoint(trigger); await checkpointTask?.value
        await persistence?.state(.paused)
    }

    func roomDone() {
        guard mode == .house,state == .scanning else { return }
        latestRoom = nil
        finishingHouse = false; state = .processing
        captureView.captureSession.stop(pauseARSession:false)
    }
    private func saveWorldMapCandidate() {
        guard let persistence else { return }
        arSession.getCurrentWorldMap { map,_ in
            guard let map else { return }
            Task {
                do {
                    let data = try await Task.detached(priority:.utility) { try NSKeyedArchiver.archivedData(withRootObject:map,requiringSecureCoding:true) }.value
                    try await persistence.write(data,key:"world-map")
                } catch { await persistence.recordFailure(error) }
            }
        }
    }
    func nextRoom() { guard active,state == .roomSaved else { return }; run() }
    func retryFinish() {
        guard active,let persistence else { return }
        state = .processing; finishingHouse = true
        Task { [weak self] in
            do {
                if let pending = self?.pendingRoom {
                    try await persistence.room(pending); self?.pendingRoom = nil
                    if self?.mode == .room {
                        self?.state = .finished(.init(scan:pending.scan,capturedRoomData:pending.raw,usdzData:nil,usdzMeshData:nil)); return
                    }
                }
                self?.finishHouse()
            } catch { self?.state = .failed(.storageFailed(error.localizedDescription)) }
        }
    }

    private func finishHouse() {
        guard mode == .house,state == .processing,let persistence else { return }
        state = .merging
        Task { [weak self] in
            do {
                await persistence.state(.finalizing)
                let saved = try await persistence.rooms().filter { !$0.partial }
                guard !saved.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                let rooms = try await Task.detached(priority:.userInitiated) {
                    try saved.map { try JSONDecoder().decode(CapturedRoom.self,from:$0.raw) }
                }.value
                let structure = try await StructureBuilder(options:[.beautifyObjects]).capturedStructure(from:rooms)
                self?.receive(structure:structure)
            } catch {
                await persistence.state(.failed)
                if self?.active == true { self?.state = .failed(.scanFailed(Self.describe(error))) }
            }
        }
    }

    func cancel() {
        flushCheckpoint(.pause)
        Task { await checkpointTask?.value; await persistence?.state(.paused) }
        active = false
        captureView.captureSession.stop()
        state = .failed(.scanCancelled)
    }

    func stop() {
        checkpointTicker?.cancel(); checkpointTicker = nil
        cameraWatchdog?.cancel(); cameraWatchdog = nil
        active = false
        if state == .scanning {
            captureView.captureSession.stop()
            state = .idle
        }
        // House capture keeps tracking alive between rooms; always release the camera on dismissal.
        arSession.pause()
        CaptureAudioSession.release(audioOwner)
    }

    // MARK: - RoomPlan Result

    private func receive(room: CapturedRoom?, error: (any Error)?) {
        guard active else { return }
        if let error {
            UserDefaults.standard.set((error as NSError).domain,forKey:"scan.lastFailureDomain")
            UserDefaults.standard.set((error as NSError).code,forKey:"scan.lastFailureCode")
            Task { [weak self] in
                await self?.flushAndPause(.interruption)
                self?.state = .failed(.scanFailed(Self.describe(error)))
            }
            return
        }
        guard state == .processing else { return }
        guard let room else { state = .failed(.scanFailed("no result")); return }
        if mode == .house {
            guard let persistence else { state = .failed(.storageFailed("Missing scan session")); return }
            Task { [weak self] in
                await self?.checkpointTask?.value
                do {
                    let value = try await Task.detached(priority:.utility) {
                        let scan = CapturedRoomAdapter.scanInput(from:room)
                        return try PersistedRoom(scan:scan,raw:CapturedRoomAdapter.encode(room),partial:false,
                            thumbnail:PlanRenderer.thumbnailPNG(for:FloorPlanBuilder().build(from:scan,name:"")))
                    }.value
                    self?.pendingRoom = value
                    try await persistence.room(value)
                    self?.pendingRoom = nil
                    self?.saveWorldMapCandidate()
                    guard let self,self.active else { return }
                    self.latestRoom = nil
                    if self.finishingHouse { self.finishHouse() } else { self.state = .roomSaved }
                } catch { self?.state = .failed(.storageFailed(error.localizedDescription)) }
            }
            return
        }
        Task { [weak self] in
            await self?.checkpointTask?.value
            do {
                let result = try await Task.detached(priority:.utility) {
                    let data = try CapturedRoomAdapter.encode(room),scan = CapturedRoomAdapter.scanInput(from:room)
                    return ScanResult(scan:scan,capturedRoomData:data,usdzData:nil,usdzMeshData:nil)
                }.value
                self?.pendingRoom = .init(scan:result.scan,raw:result.capturedRoomData,partial:false)
                if let value = self?.pendingRoom { try await self?.persistence?.room(value) }
                self?.pendingRoom = nil
                self?.state = .finished(result)
            } catch { self?.state = .failed(.storageFailed(error.localizedDescription)) }
        }
    }

    private func receive(structure: CapturedStructure) {
        guard active else { return }
        do {
            let data = try CapturedStructureAdapter.encode(structure)
            let usdz: Data? = nil // Optional exports are generated from saved geometry on demand.
            var rooms: [UUID: HouseScanResult.RoomCapture] = [:]
            for room in structure.rooms {
                rooms[room.identifier] = HouseScanResult.RoomCapture(capturedRoomData: try CapturedRoomAdapter.encode(room),
                                                                     usdzData: nil, usdzMeshData: nil)
            }
            let input = CapturedStructureAdapter.structureInput(from: structure)
            state = .finishedHouse(HouseScanResult(structure: input, capturedStructureData: data, usdzData: usdz, rooms: rooms))
        } catch {
            state = .failed(.scanFailed(error.localizedDescription))
        }
    }

    /// User-friendly messages for common RoomPlan errors.
    static func describe(_ error: any Error) -> String {
        let text = String(describing: error)
        let known: [(String, String)] = [
            ("exceedSceneSizeLimit", "error.roomplan.tooLarge"),
            ("lowTexture", "error.roomplan.lowTexture"),
            ("deviceTooHot", "error.roomplan.tooHot"),
            ("worldTrackingFailure", "error.roomplan.trackingLost"),
            ("insufficientInput", "error.roomplan.insufficient"),
            ("deviceNotSupported", "error.unsupportedDevice"),
            ("invalidRoomLocation", "error.roomplan.invalidRoomLocation"),
            ("invalidInput", "error.roomplan.invalidInput"),
        ]
        if let (_, key) = known.first(where: { text.contains($0.0) }) {
            return String(localized: String.LocalizationValue(key), bundle: .main, locale: AppLanguage.locale)
        }
        return error.localizedDescription
    }
}

/// `RoomCaptureView` delegate. Protocol requires `NSCoding` (view is
/// archivable): stub implementation, object is never archived.
final class CaptureViewDelegateProxy: NSObject, RoomCaptureViewDelegate {
    var onResult: ((CapturedRoom?, (any Error)?) -> Void)?

    override init() { super.init() }
    required init?(coder: NSCoder) { nil }
    func encode(with coder: NSCoder) {}

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?) -> Bool {
        if let error { onResult?(nil, error); return false }
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) {
        onResult?(processedResult, error)
    }
}
#endif

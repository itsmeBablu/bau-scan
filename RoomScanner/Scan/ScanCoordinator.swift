#if canImport(RoomPlan)
import Foundation
import Observation
import ARKit
import RoomPlan
import AVFoundation

/// Drives RoomPlan capture. House mode captures connected space continuously,
/// then builds a structure after the user finishes once.
@Observable
@MainActor
final class ScanCoordinator {
    enum State: Equatable {
        case idle, scanning, processing
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
    private(set) var capturedRooms: [CapturedRoom] = []
    let arSession: ARSession
    let captureView: RoomCaptureView
    /// `RoomCaptureViewDelegate` requires `NSCoding`: carried by dedicated helper object.
    private let delegateProxy = CaptureViewDelegateProxy()

    static var isSupported: Bool { RoomCaptureSession.isSupported }

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
                    if granted { self.run() } else { self.active = false; self.state = .failed(.cameraDenied) }
                }
            }
        default:
            run()
        }
    }

    private func run() {
        cameraDiagnostic = nil
        guard active else { return }
        if mode == .house {
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
        captureView.captureSession.run(configuration: config)
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
        guard state == .scanning else { return }
        state = .processing
        if mode == .house { captureView.captureSession.stop(pauseARSession: false) } else { captureView.captureSession.stop() }
    }

    /// House mode: merges captured rooms (`StructureBuilder`) and prepares result.
    private func finishHouse() {
        guard mode == .house, state == .processing, !capturedRooms.isEmpty else { return }
        state = .merging
        captureView.captureSession.stop()
        let rooms = capturedRooms
        Task { [weak self] in
            do {
                let structure = try await StructureBuilder(options: [.beautifyObjects]).capturedStructure(from: rooms)
                self?.receive(structure: structure)
            } catch {
                if self?.active == true { self?.state = .failed(.scanFailed(Self.describe(error))) }
            }
        }
    }

    func cancel() {
        active = false
        captureView.captureSession.stop()
        state = .failed(.scanCancelled)
    }

    func stop() {
        cameraWatchdog?.cancel(); cameraWatchdog = nil
        active = false
        if state == .scanning {
            captureView.captureSession.stop()
            state = .idle
        }
        // House capture keeps tracking alive between rooms; always release the camera on dismissal.
        arSession.pause()
    }

    // MARK: - RoomPlan Result

    private func receive(room: CapturedRoom?, error: (any Error)?) {
        guard active else { return }
        if let error {
            state = .failed(.scanFailed(Self.describe(error)))
            return
        }
        guard state == .processing else { return }
        guard let room else { state = .failed(.scanFailed("no result")); return }
        if mode == .house {
            capturedRooms.append(room)
            // The user walks through the connected space in one capture and finishes once.
            // Keep the existing StructureBuilder/package pipeline, without an intermediate prompt.
            finishHouse()
            return
        }
        do {
            let data = try CapturedRoomAdapter.encode(room)
            let usdz = try? CapturedRoomAdapter.usdzData(for: room)
            let usdzMesh = try? CapturedRoomAdapter.usdzData(for: room, options: .mesh)
            let scan = CapturedRoomAdapter.scanInput(from: room)
            state = .finished(ScanResult(scan: scan, capturedRoomData: data, usdzData: usdz, usdzMeshData: usdzMesh))
        } catch {
            state = .failed(.scanFailed(error.localizedDescription))
        }
    }

    private func receive(structure: CapturedStructure) {
        guard active else { return }
        do {
            let data = try CapturedStructureAdapter.encode(structure)
            let usdz = try? CapturedStructureAdapter.usdzData(for: structure)
            var rooms: [UUID: HouseScanResult.RoomCapture] = [:]
            for room in structure.rooms {
                rooms[room.identifier] = HouseScanResult.RoomCapture(capturedRoomData: try CapturedRoomAdapter.encode(room),
                                                                     usdzData: try? CapturedRoomAdapter.usdzData(for: room),
                                                                     usdzMeshData: try? CapturedRoomAdapter.usdzData(for: room, options: .mesh))
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
            return String(localized: String.LocalizationValue(key), bundle: .main)
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

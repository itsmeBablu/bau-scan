#if canImport(RoomPlan)
import Foundation
import Observation
import ARKit
import RoomPlan
import AVFoundation

/// Drives a RoomPlan session: manages the `ARSession` (reused across rooms in
/// house mode), the `RoomCaptureView`, and receives results.
///
/// House mode: each room ends with `stop(pauseARSession: false)` so
/// subsequent rooms share world coordinates; `finishHouse()` merges `CapturedRoom`s with
/// `StructureBuilder` into a `CapturedStructure`.
@Observable
@MainActor
final class ScanCoordinator {
    enum State: Equatable {
        case idle, scanning, processing
        case finished(ScanResult)
        /// House mode: room captured, awaiting 'Next Room' or 'Finish'.
        case roomCaptured(Int)
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
    let mode: ScanMode
    /// Rooms captured in house mode (shared world coordinate space).
    private(set) var capturedRooms: [CapturedRoom] = []
    let arSession: ARSession
    let captureView: RoomCaptureView
    /// `RoomCaptureViewDelegate` requires `NSCoding`: carried by dedicated helper object.
    private let delegateProxy = CaptureViewDelegateProxy()

    static var isSupported: Bool { RoomCaptureSession.isSupported }

    init(mode: ScanMode = .room, arSession: ARSession = ARSession()) {
        self.mode = mode
        self.arSession = arSession
        self.captureView = RoomCaptureView(frame: .zero, arSession: arSession)
        delegateProxy.onResult = { [weak self] room, error in
            Task { @MainActor in self?.receive(room: room, error: error) }
        }
        captureView.delegate = delegateProxy
    }

    /// Starts scan (requests camera permission if needed).
    func start() {
        guard Self.isSupported else { state = .failed(.unsupportedDevice); return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            state = .failed(.cameraDenied)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in granted ? self.run() : (self.state = .failed(.cameraDenied)) }
            }
        default:
            run()
        }
    }

    private func run() {
        var config = RoomCaptureSession.Configuration()
        config.isCoachingEnabled = true
        state = .scanning
        captureView.captureSession.run(configuration: config)
    }

    /// User completes room: RoomPlan post-processes and calls `didPresent`.
    /// In house mode, `ARSession` remains active for next room.
    func finish() {
        guard state == .scanning else { return }
        state = .processing
        if mode == .house { captureView.captureSession.stop(pauseARSession: false) } else { captureView.captureSession.stop() }
    }

    /// House mode: starts next room in the same coordinate space.
    func nextRoom() {
        guard mode == .house, case .roomCaptured = state else { return }
        run()
    }

    /// House mode: merges captured rooms (`StructureBuilder`) and prepares result.
    func finishHouse() {
        guard mode == .house, case .roomCaptured = state, !capturedRooms.isEmpty else { return }
        state = .merging
        captureView.captureSession.stop()
        let rooms = capturedRooms
        Task { [weak self] in
            do {
                let structure = try await StructureBuilder(options: [.beautifyObjects]).capturedStructure(from: rooms)
                self?.receive(structure: structure)
            } catch {
                self?.state = .failed(.scanFailed(Self.describe(error)))
            }
        }
    }

    func cancel() {
        captureView.captureSession.stop()
        state = .failed(.scanCancelled)
    }

    // MARK: - RoomPlan Result

    private func receive(room: CapturedRoom?, error: (any Error)?) {
        if let error {
            state = .failed(.scanFailed(Self.describe(error)))
            return
        }
        guard let room else { state = .failed(.scanFailed("no result")); return }
        if mode == .house {
            capturedRooms.append(room)
            state = .roomCaptured(capturedRooms.count)
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

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?) -> Bool { true }

    func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) {
        onResult?(processedResult, error)
    }
}
#endif

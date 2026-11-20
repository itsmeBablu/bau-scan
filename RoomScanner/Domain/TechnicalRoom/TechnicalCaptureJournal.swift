import Foundation

/// Retains copied capture evidence for the lifetime of the survey, including interruptions.
/// Bounded retention is explicit: evictions are counted and shown to the user. T4 owns disk persistence.
struct TechnicalCaptureJournal: Codable, Equatable {
    struct Event: Codable, Equatable {
        enum Kind: String, Codable { case started, interrupted, stopped, trackingChanged, referenceDefined, referenceLocked, checkpoint, recoverySaved, recoveryStarted, failure }
        let timestamp: Double
        let kind: Kind
        let message: String
        let alignmentVerified: Bool
        var referenceFrame: TechnicalTransform? = nil
        var checkpoint: TechnicalAlignmentSurvey.Checkpoint? = nil
    }
    private(set) var frames: [TechnicalFrameRecord] = []
    private(set) var depths: [TechnicalDepthSnapshot] = []
    private(set) var meshes: [TechnicalMeshSnapshot] = []
    private(set) var events: [Event] = []
    private(set) var droppedFrames = 0
    private(set) var droppedSnapshots = 0
    private(set) var droppedEvents = 0
    private(set) var snapshotBytes = 0
    private let frameCapacity: Int
    private let eventCapacity: Int
    private let snapshotBudget: Int

    init(frameCapacity: Int = 3600, eventCapacity: Int = 2000, snapshotBudget: Int = 64 * 1_048_576) {
        self.frameCapacity = max(1, frameCapacity)
        self.eventCapacity = max(1, eventCapacity)
        self.snapshotBudget = max(1, snapshotBudget)
    }

    var retentionLimited: Bool { droppedFrames + droppedSnapshots + droppedEvents > 0 }

    mutating func append(_ frame: TechnicalFrameRecord) {
        if frames.count == frameCapacity { frames.removeFirst(); droppedFrames += 1 }
        frames.append(frame)
    }
    mutating func append(_ event: Event) {
        if events.count == eventCapacity { events.removeFirst(); droppedEvents += 1 }
        events.append(event)
    }
    @discardableResult mutating func append(_ depth: TechnicalDepthSnapshot) -> Bool {
        let bytes = Self.bytes(depth)
        guard reserve(bytes: bytes) else { return false }
        depths.append(depth); snapshotBytes += bytes
        return true
    }
    @discardableResult mutating func append(_ mesh: TechnicalMeshSnapshot) -> Bool {
        let bytes = Self.bytes(mesh)
        guard reserve(bytes: bytes) else { return false }
        meshes.append(mesh); snapshotBytes += bytes
        return true
    }
    private mutating func reserve(bytes: Int) -> Bool {
        guard bytes <= snapshotBudget else { droppedSnapshots += 1; return false }
        while snapshotBytes + bytes > snapshotBudget {
            if let depth = depths.first, meshes.first == nil || depth.timestamp <= meshes[0].timestamp {
                snapshotBytes -= Self.bytes(depths.removeFirst())
            } else if !meshes.isEmpty {
                snapshotBytes -= Self.bytes(meshes.removeFirst())
            } else { break }
            droppedSnapshots += 1
        }
        return true
    }
    private static func bytes(_ depth: TechnicalDepthSnapshot) -> Int {
        depth.depthMetres.count * MemoryLayout<Float?>.stride + (depth.confidence?.count ?? 0) +
        (depth.cameraTransform.count + depth.intrinsics.count) * MemoryLayout<Double>.stride + 256
    }
    private static func bytes(_ mesh: TechnicalMeshSnapshot) -> Int {
        mesh.patches.reduce(256) { $0 + $1.vertices.count * MemoryLayout<TechnicalPoint3>.stride + $1.triangleIndices.count * 4 + 128 }
    }
}

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
    private var snapshotOrder: [Bool] = [] // true = depth; false = mesh, independent of AR session time origins
    private let frameCapacity: Int
    private let eventCapacity: Int
    private let snapshotBudget: Int

    init(frameCapacity: Int = 3600, eventCapacity: Int = 2000, snapshotBudget: Int = 64 * 1_048_576) {
        self.frameCapacity = max(1, frameCapacity)
        self.eventCapacity = max(1, eventCapacity)
        self.snapshotBudget = max(1, snapshotBudget)
    }

    var retentionLimited: Bool { droppedFrames > 0 || droppedSnapshots > 0 || droppedEvents > 0 }

    enum JournalError: Error { case invalidEvidence }
    func validate() throws {
        guard frameCapacity > 0, frameCapacity <= 3600, eventCapacity > 0, eventCapacity <= 2000,
              snapshotBudget > 0, snapshotBudget <= 64 * 1_048_576,
              frames.count <= frameCapacity, events.count <= eventCapacity,
              droppedFrames >= 0, droppedSnapshots >= 0, droppedEvents >= 0,
              snapshotOrder.count == depths.count + meshes.count,
              snapshotOrder.filter({ $0 }).count == depths.count,
              snapshotBytes == depths.reduce(0, { $0 + Self.bytes($1) }) + meshes.reduce(0, { $0 + Self.bytes($1) }),
              snapshotBytes <= snapshotBudget else { throw JournalError.invalidEvidence }
        for frame in frames {
            guard frame.timestamp.isFinite, frame.cameraTransform.count == 16, frame.intrinsics.count == 9,
                  (frame.cameraTransform + frame.intrinsics).allSatisfy(\.isFinite), frame.imageWidth > 0, frame.imageHeight > 0 else { throw JournalError.invalidEvidence }
        }
        for depth in depths {
            guard depth.timestamp.isFinite, depth.width > 0, depth.height > 0, depth.width <= 1024, depth.height <= 1024,
                  depth.depthMetres.count == depth.width * depth.height,
                  depth.confidence == nil || depth.confidence?.count == depth.depthMetres.count,
                  depth.depthMetres.allSatisfy({ $0 == nil || ($0!.isFinite && $0! > 0) }),
                  depth.cameraTransform.count == 16, depth.intrinsics.count == 9,
                  (depth.cameraTransform + depth.intrinsics).allSatisfy(\.isFinite), depth.imageWidth > 0, depth.imageHeight > 0 else { throw JournalError.invalidEvidence }
        }
        for mesh in meshes {
            guard mesh.timestamp.isFinite, mesh.patches.reduce(0, { $0 + $1.vertices.count }) <= 250_000,
                  mesh.patches.allSatisfy({ patch in patch.vertices.allSatisfy(TechnicalPointEditing.valid) &&
                      patch.triangleIndices.count % 3 == 0 && patch.triangleIndices.allSatisfy { Int($0) < patch.vertices.count }
                  }) else { throw JournalError.invalidEvidence }
        }
    }

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
        depths.append(depth); snapshotOrder.append(true); snapshotBytes += bytes
        return true
    }
    @discardableResult mutating func append(_ mesh: TechnicalMeshSnapshot) -> Bool {
        let bytes = Self.bytes(mesh)
        guard reserve(bytes: bytes) else { return false }
        meshes.append(mesh); snapshotOrder.append(false); snapshotBytes += bytes
        return true
    }
    private mutating func reserve(bytes: Int) -> Bool {
        guard bytes <= snapshotBudget else { droppedSnapshots += 1; return false }
        while snapshotBytes + bytes > snapshotBudget {
            guard !snapshotOrder.isEmpty else { return false }
            if snapshotOrder.removeFirst() {
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

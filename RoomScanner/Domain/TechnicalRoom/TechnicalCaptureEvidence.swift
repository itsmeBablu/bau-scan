import Foundation

/// An unrotated camera image paired with depth from the same AR frame.
/// Image pixels and depth calibration stay in native camera orientation.
struct TechnicalCaptureKeyframe: Codable, Equatable, Identifiable {
    var id: UUID
    var jpegData: Data
    var jpegWidth: Int
    var jpegHeight: Int
    var depth: TechnicalDepthSnapshot
    var userPhoto: Bool? = nil
    var googlePhotosURL: URL? = nil

    func validate() throws {
        var journal = TechnicalCaptureJournal()
        journal.append(depth)
        try journal.validate()
        let m = depth.cameraTransform, k = depth.intrinsics
        let axes = [TechnicalPoint3(x: m[0],y: m[1],z: m[2]),.init(x: m[4],y: m[5],z: m[6]),.init(x: m[8],y: m[9],z: m[10])]
        guard k[0] > 0,k[4] > 0,abs(k[8]-1) < 0.001,
              abs(m[3])+abs(m[7])+abs(m[11])+abs(m[15]-1) < 0.001,
              axes.allSatisfy({ abs(MEPVector.dot($0,$0)-1) < 0.001 }),
              abs(MEPVector.dot(axes[0],axes[1]))+abs(MEPVector.dot(axes[1],axes[2]))+abs(MEPVector.dot(axes[0],axes[2])) < 0.001,
              MEPVector.dot(MEPVector.cross(axes[0],axes[1]),axes[2]) > 0.999 else { throw TechnicalCaptureJournal.JournalError.invalidEvidence }
        if let link = googlePhotosURL {
            guard link.scheme == "https",link.host == "photos.google.com",link.user == nil,link.password == nil else { throw TechnicalCaptureJournal.JournalError.invalidEvidence }
        }
        guard jpegData.count >= 4, jpegData.count <= 4 * 1_048_576,
              jpegData.starts(with: [0xff, 0xd8]), jpegWidth > 0, jpegHeight > 0,
              jpegWidth <= 1600, jpegHeight <= 1600,
              abs(Double(jpegWidth) / Double(jpegHeight) - Double(depth.imageWidth) / Double(depth.imageHeight)) < 0.01 else {
            throw TechnicalCaptureJournal.JournalError.invalidEvidence
        }
    }
    var estimatedBytes: Int { jpegData.count + depth.depthMetres.count * MemoryLayout<Float?>.stride + (depth.confidence?.count ?? 0) + 512 }
    var confidentDepthFraction: Double {
        guard !depth.depthMetres.isEmpty else { return 0 }
        let count = depth.depthMetres.indices.filter {
            depth.depthMetres[$0] != nil && (depth.confidence?[$0] ?? 0) >= 1
        }.count
        return Double(count) / Double(depth.depthMetres.count)
    }
}

struct TechnicalCaptureEvidence: Codable, Equatable {
    private(set) var keyframes: [TechnicalCaptureKeyframe] = []
    private(set) var droppedKeyframes = 0
    static let budget = 48 * 1_048_576
    var bytes: Int { keyframes.reduce(0) { $0 + $1.estimatedBytes } }
    func withoutImageBytes() -> Self {
        var copy = self
        for i in copy.keyframes.indices { copy.keyframes[i].jpegData = Data() }
        return copy
    }
    mutating func restoreImages(_ load: (UUID) throws -> Data) rethrows {
        for i in keyframes.indices { keyframes[i].jpegData = try load(keyframes[i].id) }
    }
    mutating func append(_ frame: TechnicalCaptureKeyframe) throws {
        try frame.validate()
        guard !keyframes.contains(where: { $0.id == frame.id }), frame.estimatedBytes <= Self.budget else {
            throw TechnicalCaptureJournal.JournalError.invalidEvidence
        }
        var kept = keyframes
        var dropped = 0
        while kept.count >= 32 || kept.reduce(0, { $0+$1.estimatedBytes }) + frame.estimatedBytes > Self.budget {
            guard let i = kept.firstIndex(where: { $0.userPhoto != true }) else { throw TechnicalCaptureJournal.JournalError.invalidEvidence }
            kept.remove(at: i); dropped += 1
        }
        kept.append(frame); keyframes = kept; droppedKeyframes += dropped
    }
    mutating func setGooglePhotosURL(_ url: URL, for id: UUID) throws {
        guard let i = keyframes.firstIndex(where: { $0.id == id }),keyframes[i].userPhoto == true else { throw TechnicalCaptureJournal.JournalError.invalidEvidence }
        var updated = keyframes[i]; updated.googlePhotosURL = url
        try updated.validate(); keyframes[i] = updated
    }
    func validate() throws {
        guard keyframes.count <= 32, bytes <= Self.budget, droppedKeyframes >= 0,
              Set(keyframes.map(\.id)).count == keyframes.count else { throw TechnicalCaptureJournal.JournalError.invalidEvidence }
        for frame in keyframes { try frame.validate() }
    }
}

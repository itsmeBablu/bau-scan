import Foundation

/// Capture permission is revoked after any interruption until alignment is checked.
struct TechnicalCaptureState: Equatable {
    enum Phase: String { case idle, capturing, alignmentRequired, stopped, failed }
    private(set) var phase: Phase = .idle
    private(set) var trackingNormal = false
    private(set) var checkpointResidualMm: Double?
    var canAnnotate: Bool { phase == .capturing && trackingNormal && checkpointResidualMm != nil }

    mutating func start() { phase = .alignmentRequired; trackingNormal = false; checkpointResidualMm = nil }
    mutating func tracking(normal: Bool) {
        guard phase != .stopped && phase != .idle else { return }
        trackingNormal = normal
        if !normal && phase != .stopped { phase = .alignmentRequired; checkpointResidualMm = nil }
    }
    mutating func interrupt() {
        guard phase != .stopped && phase != .idle else { return }
        phase = .alignmentRequired; trackingNormal = false; checkpointResidualMm = nil
    }
    mutating func verify(residualMm: Double, thresholdMm: Double) {
        guard phase != .stopped, trackingNormal, residualMm.isFinite, residualMm >= 0,
              thresholdMm.isFinite, thresholdMm > 0 else { return }
        checkpointResidualMm = residualMm
        phase = residualMm <= thresholdMm ? .capturing : .alignmentRequired
    }
    mutating func stop() { phase = .stopped; trackingNormal = false; checkpointResidualMm = nil }
}

enum TechnicalReferenceFrame {
    enum FrameError: Error { case invalidBaseline }
    /// Gravity supplies +Y. Two floor corners establish origin and horizontal +X.
    static func transform(origin: TechnicalPoint3, xCorner: TechnicalPoint3) throws -> TechnicalTransform {
        let dx = xCorner.x - origin.x, dz = xCorner.z - origin.z
        let length = sqrt(dx * dx + dz * dz)
        guard length.isFinite, length > 0.1 else { throw FrameError.invalidBaseline }
        let x = TechnicalPoint3(x: dx / length, y: 0, z: dz / length)
        let z = TechnicalPoint3(x: -x.z, y: 0, z: x.x)
        return TechnicalTransform(
            translation: .init(x: -(x.x * origin.x + x.z * origin.z), y: -origin.y,
                               z: -(z.x * origin.x + z.z * origin.z)),
            xAxis: .init(x: x.x, y: 0, z: z.x),
            yAxis: .init(x: 0, y: 1, z: 0),
            zAxis: .init(x: x.z, y: 0, z: z.z))
    }

    static func apply(_ t: TechnicalTransform, to p: TechnicalPoint3) -> TechnicalPoint3 {
        .init(x: t.translation.x + t.xAxis.x * p.x + t.yAxis.x * p.y + t.zAxis.x * p.z,
              y: t.translation.y + t.xAxis.y * p.x + t.yAxis.y * p.y + t.zAxis.y * p.z,
              z: t.translation.z + t.xAxis.z * p.x + t.yAxis.z * p.y + t.zAxis.z * p.z)
    }

    /// Inverse of a rigid orthonormal shell-to-room transform.
    static func inverseApply(_ t: TechnicalTransform, to p: TechnicalPoint3) -> TechnicalPoint3 {
        let x = p.x - t.translation.x, y = p.y - t.translation.y, z = p.z - t.translation.z
        return .init(x: t.xAxis.x * x + t.xAxis.y * y + t.xAxis.z * z,
                     y: t.yAxis.x * x + t.yAxis.y * y + t.yAxis.z * z,
                     z: t.zAxis.x * x + t.zAxis.y * y + t.zAxis.z * z)
    }
}

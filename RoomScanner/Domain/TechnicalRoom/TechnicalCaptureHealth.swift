import Foundation

struct TechnicalCaptureHealth {
    struct Sample {
        let trackingNormal: Bool
        let fps: Double
        let residentMemoryBytes: UInt64?
        let ambientIntensity: Double?
        let depthCoverage: Double?
        let elapsedSeconds: Double
    }
    static func warnings(for sample: Sample) -> [String] {
        var warnings: [String] = []
        if !sample.trackingNormal { warnings.append("Tracking limited — alignment is unverified; annotations are locked.") }
        if sample.elapsedSeconds > 3, sample.fps.isFinite, sample.fps < 20 {
            warnings.append("Low frame rate — move slowly and reduce capture workload.")
        }
        if let memory = sample.residentMemoryBytes, memory > 750 * 1_048_576 {
            warnings.append("High memory use — save evidence and reduce snapshot capture.")
        }
        if let light = sample.ambientIntensity, light.isFinite, light < 150 {
            warnings.append("Low light — improve lighting for tracking and depth capture.")
        }
        if let coverage = sample.depthCoverage, coverage < 0.5 {
            warnings.append("Incomplete depth — revisit missing surfaces from another angle.")
        } else if sample.depthCoverage == nil, sample.elapsedSeconds > 3 {
            warnings.append("Scene depth is unavailable — LiDAR depth validation is pending.")
        }
        return warnings
    }
}

import Foundation

/// Survey evidence is platform neutral. Passing a checkpoint is not an accuracy certification.
struct TechnicalAlignmentSurvey: Codable, Equatable {
    enum SurveyError: LocalizedError {
        case lockedReference, missingReference, invalidCheckpoint, checkpointOnBaseline
        var errorDescription: String? {
            switch self {
            case .lockedReference: "The reference frame is locked because annotations exist. Start a new survey to change it."
            case .missingReference: "Define the origin and +X floor corner first."
            case .invalidCheckpoint: "Checkpoint coordinates, time and tolerance must be finite; tolerance must be positive."
            case .checkpointOnBaseline: "Use an independent third checkpoint at least 10 cm away from the origin–X baseline."
            }
        }
    }
    struct Checkpoint: Codable, Equatable, Identifiable {
        let id: UUID
        let timestamp: Double
        let expected: TechnicalPoint3
        let observedInSession: TechnicalPoint3
        let observedInRoom: TechnicalPoint3
        let residualMm: Double
        let thresholdMm: Double
        var accepted: Bool { residualMm <= thresholdMm }
    }
    private(set) var referenceFrame: TechnicalTransform?
    private(set) var origin: TechnicalPoint3?
    private(set) var xCorner: TechnicalPoint3?
    private(set) var referenceLocked = false
    private(set) var checkpoints: [Checkpoint] = []

    mutating func define(origin: TechnicalPoint3, xCorner: TechnicalPoint3) throws {
        guard !referenceLocked else { throw SurveyError.lockedReference }
        let transform = try TechnicalReferenceFrame.transform(origin: origin, xCorner: xCorner)
        self.referenceFrame = transform; self.origin = origin; self.xCorner = xCorner
        checkpoints = []
    }

    mutating func lockReference() { if referenceFrame != nil { referenceLocked = true } }

    func validate() throws {
        guard let referenceFrame else {
            guard origin == nil, xCorner == nil, !referenceLocked, checkpoints.isEmpty else { throw SurveyError.invalidCheckpoint }
            return
        }
        guard let origin, let xCorner, try TechnicalReferenceFrame.transform(origin: origin, xCorner: xCorner) == referenceFrame else { throw SurveyError.invalidCheckpoint }
        for checkpoint in checkpoints {
            let transformed = TechnicalReferenceFrame.apply(referenceFrame, to: checkpoint.observedInSession)
            guard [checkpoint.timestamp, checkpoint.thresholdMm, checkpoint.residualMm, checkpoint.expected.x, checkpoint.expected.y, checkpoint.expected.z].allSatisfy(\.isFinite),
                  checkpoint.thresholdMm > 0, checkpoint.residualMm >= 0, abs(checkpoint.expected.z) > 0.1,
                  transformed.distance(to: checkpoint.observedInRoom) < 1e-8,
                  abs(transformed.distance(to: checkpoint.expected) * 1000 - checkpoint.residualMm) < 1e-6 else { throw SurveyError.invalidCheckpoint }
        }
    }

    @discardableResult mutating func check(observed: TechnicalPoint3, expected: TechnicalPoint3,
                                          thresholdMm: Double, timestamp: Double) throws -> Checkpoint {
        guard let referenceFrame else { throw SurveyError.missingReference }
        guard [observed.x, observed.y, observed.z, expected.x, expected.y, expected.z, thresholdMm, timestamp].allSatisfy(\.isFinite),
              thresholdMm > 0 else { throw SurveyError.invalidCheckpoint }
        guard abs(expected.z) > 0.1 else { throw SurveyError.checkpointOnBaseline }
        let roomPoint = TechnicalReferenceFrame.apply(referenceFrame, to: observed)
        let checkpoint = Checkpoint(id: UUID(), timestamp: timestamp, expected: expected, observedInSession: observed,
                                    observedInRoom: roomPoint, residualMm: roomPoint.distance(to: expected) * 1000,
                                    thresholdMm: thresholdMm)
        guard checkpoint.residualMm.isFinite else { throw SurveyError.invalidCheckpoint }
        checkpoints.append(checkpoint)
        return checkpoint
    }
}

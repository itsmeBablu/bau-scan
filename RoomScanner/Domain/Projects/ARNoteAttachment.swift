import Foundation

/// Explicit selection wins in capture. Otherwise only a nearby spatial text pin
/// is eligible; voice clips stay separate records, so a new clip cannot erase one.
enum ARNoteAttachment {
    static func nearest(to point:TechnicalPoint3,in notes:[ARNote],radius:Double = 0.35) -> ARNote? {
        notes.filter { $0.anchorPinID == nil && $0.audioFileName == nil && $0.position != nil }
            .compactMap { note -> (ARNote,Double)? in
                guard let p = note.position else { return nil }
                let distance = p.distance(to:point)
                return distance <= radius ? (note,distance) : nil
            }.min { $0.1 == $1.1 ? $0.0.id.uuidString < $1.0.id.uuidString : $0.1 < $1.1 }?.0
    }
}

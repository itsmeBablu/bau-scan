import Foundation

enum NoteRecordingPolicy {
    static func action(seconds: Double,cancelled: Bool) -> Bool {
        !cancelled && seconds.isFinite && seconds >= 0.5 && seconds <= 60.1
    }
    static func gesture(x: Double,y: Double) -> (cancel: Bool,lock: Bool) { (x < -70,y < -70) }
}

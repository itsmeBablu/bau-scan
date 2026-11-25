import Foundation

/// Raw values correspond to AVAudioSession's documented notification enums.
/// Input-route loss is distinguished from an output-only route disappearing.
enum RecorderEventPolicy {
    enum Event { case interruption(UInt?), route(UInt?,inputLost:Bool), mediaReset, background }
    static func stopReason(_ event:Event,sinceActivation:TimeInterval) -> String? {
        switch event {
        case .interruption(let type): return type == 1 ? "Audio interruption began" : nil
        case .route(let reason,let inputLost):
            guard sinceActivation >= 0.5 else { return nil }
            return (reason == 2 && inputLost) || reason == 7 ? "Recording input unavailable" : nil
        case .mediaReset: return "Audio services reset"
        case .background: return "App entered background"
        }
    }
}
struct RecorderStateMachine {
    enum Phase { case idle, preparing, recording }
    private(set) var phase = Phase.idle
    private(set) var generation = 0
    mutating func prepare() -> Int { generation += 1; phase = .preparing; return generation }
    mutating func started(_ request:Int) -> Bool {
        guard request == generation,phase == .preparing else { return false }
        phase = .recording; return true
    }
    mutating func stop() { generation += 1; phase = .idle }
}

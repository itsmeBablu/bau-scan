import Foundation

struct ScanCheckpointPolicy {
    var interval = 15.0
    var geometryGrowth = 12
    var encodedGrowth = 512*1024
    var minimumSpacing = 3.0
    enum Trigger { case update, memoryWarning, pause, interruption, background }
    struct Sample { var time:Double; var geometry:Int; var bytes:Int }
    private(set) var last: Sample?
    func shouldSave(_ sample:Sample,trigger:Trigger) -> Bool {
        guard sample.time.isFinite,sample.geometry >= 0,sample.bytes >= 0 else { return false }
        if trigger != .update { return true }
        guard let last else { return true }
        guard sample.time-last.time >= minimumSpacing else { return false }
        return sample.time-last.time >= interval || sample.geometry-last.geometry >= geometryGrowth || sample.bytes-last.bytes >= encodedGrowth
    }
    mutating func committed(_ sample:Sample) { last = sample }
}

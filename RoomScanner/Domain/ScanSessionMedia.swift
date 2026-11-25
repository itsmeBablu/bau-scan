import Foundation

struct PersistedRoom: Codable {
    let scan: ScanInput
    let raw: Data
    let partial: Bool
    var thumbnail: Data? = nil
}

struct ScanVoiceMedia: Codable {
    let note: ARNote
    let audio: Data?
    let pose: [Double]?
    let capturedAt: Date
}
struct ScanPhotoMedia: Codable {
    let photo: SurveyPhoto
    let jpeg: Data
    var level: Int? = nil
}

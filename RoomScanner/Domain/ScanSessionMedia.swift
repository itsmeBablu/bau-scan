import Foundation
struct ScanVoiceMedia: Codable {
    let note: ARNote
    let audio: Data?
    let pose: [Double]?
    let capturedAt: Date
}
struct ScanPhotoMedia: Codable {
    let photo: SurveyPhoto
    let jpeg: Data
}

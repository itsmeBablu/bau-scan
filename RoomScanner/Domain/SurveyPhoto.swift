import Foundation

/// Camera pose is column-major, Y-up, metres. A photo is evidence, not a measurement.
struct SurveyPhoto: Codable, Equatable, Identifiable {
    var id: UUID
    var roomID: UUID?
    var number: Int
    var pose: [Double]
    var displayPose: [Double]?
    var timestamp: Double
    var capturedAt: Date?
    var deviceValidationPending = true
    var jpegPath: String { "survey-photos/\(id.uuidString).jpg" }
    var viewingPose: [Double] { displayPose ?? pose }
    enum CodingKeys: String,CodingKey { case id,roomID,number,pose,displayPose,timestamp,capturedAt,deviceValidationPending,jpegPath }
    init(id: UUID,roomID: UUID? = nil,number: Int,pose: [Double],displayPose: [Double]? = nil,timestamp: Double,capturedAt: Date? = nil) {
        self.id = id; self.roomID = roomID; self.number = number; self.pose = pose
        self.displayPose = displayPose; self.timestamp = timestamp; self.capturedAt = capturedAt
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        id = try c.decode(UUID.self,forKey:.id)
        roomID = try c.decodeIfPresent(UUID.self,forKey:.roomID)
        number = try c.decode(Int.self,forKey:.number)
        pose = try c.decode([Double].self,forKey:.pose)
        displayPose = try c.decodeIfPresent([Double].self,forKey:.displayPose)
        timestamp = try c.decode(Double.self,forKey:.timestamp)
        capturedAt = try c.decodeIfPresent(Date.self,forKey:.capturedAt)
        deviceValidationPending = try c.decodeIfPresent(Bool.self,forKey:.deviceValidationPending) ?? true
        if let path = try c.decodeIfPresent(String.self,forKey:.jpegPath),path != jpegPath { throw CocoaError(.fileReadCorruptFile) }
        try validate()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy:CodingKeys.self)
        try c.encode(id,forKey:.id); try c.encodeIfPresent(roomID,forKey:.roomID)
        try c.encode(number,forKey:.number); try c.encode(pose,forKey:.pose)
        try c.encodeIfPresent(displayPose,forKey:.displayPose); try c.encode(timestamp,forKey:.timestamp)
        try c.encodeIfPresent(capturedAt,forKey:.capturedAt); try c.encode(deviceValidationPending,forKey:.deviceValidationPending)
        try c.encode(jpegPath,forKey:.jpegPath)
    }

    func validate() throws {
        func rigid(_ m: [Double]) -> Bool {
            guard m.count == 16,m.allSatisfy(\.isFinite),abs(m[3])+abs(m[7])+abs(m[11])+abs(m[15]-1) < 0.001 else { return false }
            let x = TechnicalPoint3(x:m[0],y:m[1],z:m[2]),y = TechnicalPoint3(x:m[4],y:m[5],z:m[6]),z = TechnicalPoint3(x:m[8],y:m[9],z:m[10])
            return abs(MEPVector.dot(x,x)-1) < 0.001 && abs(MEPVector.dot(y,y)-1) < 0.001 &&
                abs(MEPVector.dot(z,z)-1) < 0.001 && MEPVector.dot(MEPVector.cross(x,y),z) > 0.999
        }
        guard number > 0, timestamp.isFinite,rigid(pose),displayPose.map(rigid) ?? true,
              capturedAt.map({ $0.timeIntervalSince1970.isFinite }) ?? true else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
    /// Each room has an independent sequence; acquisition order stays unchanged.
    static func numbered(_ photos: [Self]) -> [Self] {
        var counts: [UUID?: Int] = [:]
        return photos.map { original in
            var photo = original
            counts[photo.roomID,default:0] += 1
            photo.number = counts[photo.roomID]!
            return photo
        }
    }
    static func transformedPose(_ pose: [Double], by transform: TechnicalTransform) -> [Double] {
        guard pose.count == 16 else { return pose }
        var result = pose
        let zero = TechnicalReferenceFrame.apply(transform,to:.init(x:0,y:0,z:0))
        for col in 0..<4 {
            let point = TechnicalReferenceFrame.apply(transform,to:.init(x:pose[col*4],y:pose[col*4+1],z:pose[col*4+2]))
            result[col*4] = point.x - (col == 3 ? 0 : zero.x)
            result[col*4+1] = point.y - (col == 3 ? 0 : zero.y)
            result[col*4+2] = point.z - (col == 3 ? 0 : zero.z)
        }
        return result
    }
}

enum ScanPhotoPolicy {
    static let preferenceKey = "capture.cameraPhotos"
    static func buttonVisible(enabled: Bool, cameraRunning: Bool) -> Bool { enabled && cameraRunning }
}

struct SurveyPhotoImage: Equatable, Identifiable {
    let photo: SurveyPhoto
    let jpegData: Data
    var roomName = ""
    var id: UUID { photo.id }
    var title: String { roomName.isEmpty ? "Photo \(photo.number)" : "\(roomName) · Photo \(photo.number)" }
}

enum ScanPerformance: String, CaseIterable {
    case quality, balanced, performance
    static let preferenceKey = "capture.performance"
    var previewInterval: Double { switch self { case .quality: 0.5; case .balanced: 1; case .performance: 2 } }
    var previewVertices: Int { switch self { case .quality: 60_000; case .balanced: 30_000; case .performance: 12_000 } }
    var previewTriangles: Int { switch self { case .quality: 40_000; case .balanced: 20_000; case .performance: 8_000 } }
}

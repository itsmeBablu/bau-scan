#if os(iOS)
import ARKit
import Observation

@MainActor @Observable final class HouseSurveyPhotoCapture {
    private(set) var photos: [SurveyPhoto] = []
    private(set) var assets: [UUID:Data] = [:]
    private(set) var busy = false
    private(set) var completed = 0
    var error: String?
    func capture(session: ARSession) async {
        guard !busy else { return }
        guard let frame = session.currentFrame,frame.camera.trackingState == .normal else {
            error = "Wait for normal camera tracking before taking a photo."; return
        }
        guard photos.count < 200 else { error = "Photo limit reached. Save this scan."; return }
        busy = true
        defer { busy = false }
        let m = frame.camera.transform
        let pose = (0..<4).flatMap { c in (0..<4).map { Double(m[c][$0]) } }
        let time = frame.timestamp
        let encoded = await Task.detached(priority:.userInitiated) {
            TechnicalRoomKeyframeCollector.jpeg(frame:frame)
        }.value
        guard let encoded,assets.values.reduce(0,{ $0+$1.count })+encoded.data.count <= SurveyPhotoStore.maximumBytes else {
            error = "Photo budget reached or image encoding failed. Save this scan."; return
        }
        let photo = SurveyPhoto(id:UUID(),number:photos.count+1,pose:pose,timestamp:time,capturedAt:Date())
        photos.append(photo); assets[photo.id] = encoded.data
        completed += 1
    }
    func registered(house: House, scans: [ScanInput], alignSingleRoom: Bool) -> [SurveyPhoto] {
        let placed = photos.map { original -> SurveyPhoto in
            var photo = original
            let cameraPoint = Point2D(x:photo.pose[12],y:-photo.pose[14])
            let candidates = house.allRooms.filter { room in
                Polygon2D.contains(room.floorPolygon.map(room.transform.apply),cameraPoint)
            }
            let room: FloorPlan?
            if house.allRooms.count == 1 { room = house.allRooms.first }
            else {
                room = candidates.min { a,b in
                    func distance(_ plan: FloorPlan) -> Double {
                        guard let scan = scans.first(where: { $0.id == plan.id }) else { return .infinity }
                        return abs(photo.pose[13] - StoryDetector.floorHeight(of:scan) - 1.4)
                    }
                    return distance(a) < distance(b)
                }
            }
            guard let room,let scan = scans.first(where: { $0.id == room.id }) else { return photo }
            photo.roomID = room.id
            var rotation = room.transform.rotation
            if alignSingleRoom,let longest = scan.walls.max(by:{ $0.dimensions.x < $1.dimensions.x }) {
                var theta = atan2(-Double(longest.transform.columns.0.z),Double(longest.transform.columns.0.x))
                while theta > .pi/2 { theta -= .pi }; while theta <= -.pi/2 { theta += .pi }
                rotation -= theta
            }
            let c = cos(rotation),s = sin(rotation)
            let transform = TechnicalTransform(translation:.init(x:room.transform.translation.x,y:-StoryDetector.floorHeight(of:scan),z:-room.transform.translation.y),
                xAxis:.init(x:c,y:0,z:-s),yAxis:.init(x:0,y:1,z:0),zAxis:.init(x:s,y:0,z:c))
            photo.displayPose = SurveyPhoto.transformedPose(photo.pose,by:transform)
            return photo
        }
        return SurveyPhoto.numbered(placed)
    }
}
#endif

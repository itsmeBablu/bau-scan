#if os(iOS)
import ARKit
import AVFoundation
import CoreImage
import Observation
import RealityKit
import UIKit
import SwiftUI

/// Owns a saved-House close-up session, or passively observes the live House session.
/// Shared-session mode never changes RoomPlan's delegate, configuration or camera lifecycle.
@Observable @MainActor
final class HouseRadiatorScanCoordinator: NSObject,@preconcurrency ARSessionDelegate {
    let session: ARSession
    private let ownsSession: Bool
    private let automaticCapture: Bool
    private(set) var depthAvailable = false
    init(session: ARSession? = nil,automaticCapture: Bool = false) {
        self.session = session ?? ARSession()
        ownsSession = session == nil
        self.automaticCapture = automaticCapture
        super.init()
    }
    private(set) var frontCorners: [RadiatorPoint] = []
    private(set) var geometry: RadiatorScanGeometry?
    private(set) var viewpointCount = 0
    private(set) var sampleCount = 0
    private(set) var trackingNormal = false
    private(set) var message = "Looking for a radiator candidate. Keep the whole body and adjacent wall visible."
    private(set) var candidate: RadiatorAutomaticDetector.Candidate?
    private var previousCandidate: RadiatorAutomaticDetector.Candidate?
    private var stableDetections = 0
    private var lastDetectionTime = -Double.infinity
    private var detectionTask: Task<Void,Never>?
    private var excludedCenters: [RadiatorPoint] = []
    private(set) var error: String?
    private(set) var frozen = false
    private(set) var photo: Data?
    private(set) var previewRevision = 0
    private var lastPreviewTime = -Double.infinity
    private var active = false
    private var paused = false
    private var requestingPermission = false
    private var generation = 0
    private var lastSampleTime = -Double.infinity
    private var lastCameraPosition: RadiatorPoint?
    private var lastCameraDirection: RadiatorPoint?
    private struct Key: Hashable { let x: Int; let y: Int; let z: Int }
    private var points: [Key:[RadiatorSurfaceSample]] = [:]
    static var isSupported: Bool { ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) }

    func start() {
        guard !active,!requestingPermission,!frozen else { return }
        if !ownsSession {
            // RoomPlan owns this camera and its delegate/configuration. Observe frames only.
            active = true; paused = false
            refreshSharedFrame()
            return
        }
        guard Self.isSupported else { error = "Radiator scanning requires a LiDAR-equipped iPhone or iPad."; return }
        requestingPermission = true; generation += 1
        let request = generation
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor in
                guard let self,self.generation == request else { return }
                self.requestingPermission = false
                guard granted else { self.error = "Allow camera access in Settings to scan the radiator."; return }
                self.error = nil
                let config = ARWorldTrackingConfiguration()
                config.frameSemantics = [.sceneDepth]
                if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) { config.sceneReconstruction = .mesh }
                config.planeDetection = [.vertical,.horizontal]
                self.session.delegate = self; self.session.delegateQueue = .main
                self.active = true; self.paused = false
                self.session.run(config)
            }
        }
    }
    func pause() {
        if requestingPermission { generation += 1; requestingPermission = false }
        guard active,!paused,!frozen else { return }
        paused = true; trackingNormal = false
        generation += 1; detectionTask?.cancel(); detectionTask = nil
        if geometry == nil { candidate = nil; previousCandidate = nil; stableDetections = 0 }
        if ownsSession { session.pause() }
    }
    func resume() {
        if !active { start(); return }
        guard paused,!frozen,let config = session.configuration else { return }
        paused = false; lastSampleTime = -Double.infinity
        if ownsSession { session.run(config,options: []) }
    }
    func stop() {
        generation += 1; active = false; requestingPermission = false
        detectionTask?.cancel(); detectionTask = nil
        if ownsSession { session.pause() }
    }
    func refreshSharedFrame() {
        guard !ownsSession,let frame = session.currentFrame else { return }
        session(session,didUpdate: frame)
    }
    func acceptCandidate() {
        guard let candidate,!frozen,trackingNormal else { return }
        geometry = candidate.geometry; frontCorners = candidate.geometry.frontCorners
        self.candidate = nil; previousCandidate = nil; stableDetections = 0
        message = "Candidate selected. Move closer, then around the sides and top. Include the adjacent wall and visible rear surfaces."
    }
    func skipCandidate() {
        if let candidate { excludedCenters.append(candidate.center) }
        else if let geometry { excludedCenters.append(geometry.origin+geometry.right*(geometry.width/2)+geometry.up*(geometry.height/2)) }
        if excludedCenters.count > 100 { excludedCenters.removeFirst() }
        frozen = false; resetBounds()
    }
    func bodyRect(in size: CGSize) -> CGRect? {
        guard let body = geometry ?? candidate?.geometry else { return nil }
        return projectedRect([body.origin,body.origin+body.right*body.width,body.origin+body.up*body.height,body.origin+body.right*body.width+body.up*body.height],in: size)
    }
    func bodyRect(for radiator: HouseRadiator,in size: CGSize) -> CGRect? {
        let p = radiator.frontCorners
        guard p.count == 3 else { return nil }
        return projectedRect([p[0],p[1],p[2],p[1]+p[2]-p[0]],in: size)
    }
    private func projectedRect(_ corners: [RadiatorPoint],in size: CGSize) -> CGRect? {
        guard let frame = session.currentFrame,size.width > 0,size.height > 0 else { return nil }
        let orientation = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }?.interfaceOrientation ?? .portrait
        let projected = corners.compactMap { p -> CGPoint? in
            let world = SIMD3<Float>(Float(p.x),Float(p.y),Float(p.z))
            let camera = frame.camera.transform.inverse*SIMD4(world.x,world.y,world.z,1)
            guard camera.z < -0.05 else { return nil }
            return frame.camera.projectPoint(world,orientation: orientation,viewportSize: size)
        }
        guard projected.count == 4,projected.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let xs = projected.map(\.x),ys = projected.map(\.y)
        let rect = CGRect(x: xs.min()!,y: ys.min()!,width: xs.max()!-xs.min()!,height: ys.max()!-ys.min()!)
        let clipped = rect.intersection(CGRect(origin: .zero,size: size))
        return clipped.isNull || clipped.width < 10 || clipped.height < 10 ? nil : clipped
    }
    func resetBounds() {
        guard !frozen else { return }
        generation += 1; detectionTask?.cancel(); detectionTask = nil
        frontCorners = []; geometry = nil; candidate = nil; previousCandidate = nil; stableDetections = 0
        lastDetectionTime = -Double.infinity
        points = [:]; sampleCount = 0; viewpointCount = 0; photo = nil
        lastCameraPosition = nil; lastCameraDirection = nil
        frozen = false
        message = "Looking for a radiator candidate. Keep the whole body and adjacent wall visible."; error = nil
    }
    func finish(roomID: UUID,wallID: UUID?,preset: RadiatorMountingPreset) async throws -> HouseRadiator {
        guard let geometry else { throw HouseRadiatorSurvey.Failure.incomplete }
        let samples = points.values.flatMap { $0 }
        guard samples.count >= 30,viewpointCount >= 2 else { throw HouseRadiatorSurvey.Failure.incomplete }
        frozen = true
        if ownsSession { session.pause() }
        trackingNormal = false
        if photo == nil,let frame = session.currentFrame {
            photo = await Task.detached(priority: .utility) {
                HouseRadiatorImageEncoder.jpeg(frame.capturedImage)
            }.value
        }
        do {
            var result = try geometry.result(roomID: roomID,wallID: wallID,samples: samples,viewpoints: viewpointCount,preset: preset,photo: photo,automatic: true)
            result.identification = automaticCapture ? .automaticCandidate : .userConfirmed
            result.notes = automaticCapture ? "Automatically collected geometric candidate; radiator identity is unverified. Body envelope and wall plane are scan estimates; hidden rear clearance remains unknown without observed evidence." : "Geometry-proposed radiator candidate confirmed by user; not semantic equipment recognition. Body envelope and wall plane are scan estimates; hidden surfaces are not reconstructed."
            return result
        } catch {
            frozen = false; paused = true
            resume()
            throw error
        }
    }

    func session(_ session: ARSession,didUpdate frame: ARFrame) {
        guard active,!paused,!frozen else { return }
        let normal = frame.camera.trackingState == .normal
        if trackingNormal != normal { trackingNormal = normal }
        let depth = frame.sceneDepth ?? frame.smoothedSceneDepth
        if depthAvailable != (depth != nil) { depthAvailable = depth != nil }
        if (automaticCapture || geometry != nil || candidate != nil),frame.timestamp-lastPreviewTime >= 0.2 { lastPreviewTime = frame.timestamp; previewRevision &+= 1 }
        if !normal,geometry == nil { candidate = nil; previousCandidate = nil; stableDetections = 0 }
        let lockedCenter = geometry.map { $0.origin+$0.right*($0.width/2)+$0.up*($0.height/2) }
        if automaticCapture,let center = lockedCenter,(sampleCount < 120 || viewpointCount < 3) {
            let m = frame.camera.transform
            let camera = RadiatorPoint(x: Double(m[3].x),y: Double(m[3].y),z: Double(m[3].z))
            let forward = RadiatorPoint(x: -Double(m[2].x),y: -Double(m[2].y),z: -Double(m[2].z))
            if (center-camera).length > 3 || forward.dot((center-camera).unit) < 0.6 {
                resetBounds(); return
            }
        }
        if let candidate,geometry == nil {
            let m = frame.camera.transform
            let camera = RadiatorPoint(x: Double(m[3].x),y: Double(m[3].y),z: Double(m[3].z))
            let forward = RadiatorPoint(x: -Double(m[2].x),y: -Double(m[2].y),z: -Double(m[2].z))
            if (candidate.center-camera).length > 3 || forward.dot((candidate.center-camera).unit) < 0.6 {
                self.candidate = nil; previousCandidate = nil; stableDetections = 0
            }
        }
        if normal,candidate == nil,let depth,frame.timestamp-lastDetectionTime >= 1.2,detectionTask == nil {
            lastDetectionTime = frame.timestamp
            let request = generation,excluded = excludedCenters
            let detectionDepth = frame.smoothedSceneDepth ?? depth
            detectionTask = Task { @MainActor [weak self] in
                let found = await Task.detached(priority: .utility) { Self.detectCandidate(frame: frame,depth: detectionDepth,excluded: excluded,target: lockedCenter) }.value
                guard let self,self.generation == request else { return }
                self.detectionTask = nil
                guard self.active,!self.paused,!self.frozen,self.trackingNormal else { return }
                guard let found else { self.stableDetections = 0; self.previousCandidate = nil; return }
                if let old = self.previousCandidate,(old.center-found.center).length < 0.1,
                   abs(old.geometry.width-found.geometry.width) < 0.12,abs(old.geometry.height-found.geometry.height) < 0.12 {
                    self.stableDetections += 1
                } else { self.stableDetections = 1 }
                self.previousCandidate = found
                if self.stableDetections >= 3 {
                    if let current = self.geometry {
                        guard (found.center-(current.origin+current.right*(current.width/2)+current.up*(current.height/2))).length < 0.12,
                              found.geometry.frontNormal.dot(current.frontNormal) > 0.98,
                              abs(found.geometry.width-current.width) < 0.12,abs(found.geometry.height-current.height) < 0.12 else { return }
                        self.geometry = found.geometry; self.frontCorners = found.geometry.frontCorners
                        self.message = "Visible front measurements refined. Continue around the sides and top; hidden rear clearance stays unknown."
                    } else {
                        self.candidate = found
                        self.message = "Possible radiator found. Confirm the body is fully visible; cabinets and TVs can also match this geometry."
                        if self.automaticCapture { self.acceptCandidate() }
                    }
                }
            }
        }
        guard normal,let geometry,frame.timestamp-lastSampleTime >= 0.7,let depth else { return }
        let m = frame.camera.transform
        let camera = RadiatorPoint(x: Double(m[3].x),y: Double(m[3].y),z: Double(m[3].z))
        let direction = RadiatorPoint(x: Double(m[2].x),y: Double(m[2].y),z: Double(m[2].z))
        if let old = lastCameraPosition,let oldDirection = lastCameraDirection,
           (camera-old).length < 0.04,oldDirection.dot(direction) > cos(Double.pi/18) { return }
        lastSampleTime = frame.timestamp; lastCameraPosition = camera; lastCameraDirection = direction
        viewpointCount += 1
        let buffer = depth.depthMap
        let w = CVPixelBufferGetWidth(buffer),h = CVPixelBufferGetHeight(buffer)
        CVPixelBufferLockBaseAddress(buffer,.readOnly)
        if let confidence = depth.confidenceMap { CVPixelBufferLockBaseAddress(confidence,.readOnly) }
        defer {
            CVPixelBufferUnlockBaseAddress(buffer,.readOnly)
            if let confidence = depth.confidenceMap { CVPixelBufferUnlockBaseAddress(confidence,.readOnly) }
        }
        for y in stride(from: 1,to: h-1,by: 3) {
            for x in stride(from: 1,to: w-1,by: 3) {
                guard let sample = Self.sampleLocked(frame: frame,depth: depth,x: x,y: y,viewpoint: viewpointCount),geometry.contains(sample.point) else { continue }
                let p = sample.point
                let key = Key(x: Int((p.x*200).rounded()),y: Int((p.y*200).rounded()),z: Int((p.z*200).rounded()))
                var group = points[key] ?? []
                guard sampleCount < 8000,group.count < 2,!group.contains(where: { $0.viewpoint == viewpointCount }) else { continue }
                group.append(sample); points[key] = group; sampleCount += 1
            }
        }
        if sampleCount >= 8000 { message = "Surface sample budget reached. Retained observations are kept; finish when you have inspected the visible surfaces." }
    }
    func sessionWasInterrupted(_ session: ARSession) { trackingNormal = false }
    func sessionInterruptionEnded(_ session: ARSession) { trackingNormal = false }
    func session(_ session: ARSession,didFailWithError error: Error) { self.error = error.localizedDescription; trackingNormal = false }

    nonisolated private static func detectCandidate(frame: ARFrame,depth: ARDepthData,excluded: [RadiatorPoint],target: RadiatorPoint?) -> RadiatorAutomaticDetector.Candidate? {
        let buffer = depth.depthMap
        CVPixelBufferLockBaseAddress(buffer,.readOnly)
        if let confidence = depth.confidenceMap { CVPixelBufferLockBaseAddress(confidence,.readOnly) }
        defer {
            CVPixelBufferUnlockBaseAddress(buffer,.readOnly)
            if let confidence = depth.confidenceMap { CVPixelBufferUnlockBaseAddress(confidence,.readOnly) }
        }
        let w = CVPixelBufferGetWidth(buffer),h = CVPixelBufferGetHeight(buffer)
        let step = max(3,(max(w,h)+255)/256)
        guard w > 2,h > 2,w <= 1024,h <= 1024 else { return nil }
        let xs = Array(stride(from: 1,to: w-step,by: step)),ys = Array(stride(from: 1,to: h-step,by: step))
        let grid = ys.flatMap { y in xs.map { x in sampleLocked(frame: frame,depth: depth,x: x,y: y,viewpoint: 0,normalStep: step) } }
        let m = frame.camera.transform
        return RadiatorAutomaticDetector.detect(grid: grid,width: xs.count,height: ys.count,
            camera: .init(x: Double(m[3].x),y: Double(m[3].y),z: Double(m[3].z)),excluded: excluded,target: target)
    }

    nonisolated private static func sampleLocked(frame: ARFrame,depth: ARDepthData,x: Int,y: Int,viewpoint: Int,normalStep: Int = 1) -> RadiatorSurfaceSample? {
        let buffer = depth.depthMap
        let w = CVPixelBufferGetWidth(buffer),h = CVPixelBufferGetHeight(buffer)
        guard x >= 0,y >= 0,normalStep > 0,x+normalStep < w,y+normalStep < h,let base = CVPixelBufferGetBaseAddress(buffer),
              CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_DepthFloat32,
              let confidence = depth.confidenceMap,CVPixelBufferGetWidth(confidence) == w,CVPixelBufferGetHeight(confidence) == h,
              let confidenceBase = CVPixelBufferGetBaseAddress(confidence) else { return nil }
        let k = frame.camera.intrinsics,m = frame.camera.transform
        let imageW = Float(CVPixelBufferGetWidth(frame.capturedImage)),imageH = Float(CVPixelBufferGetHeight(frame.capturedImage))
        func point(_ x: Int,_ y: Int) -> RadiatorPoint? {
            let quality = confidenceBase.load(fromByteOffset: y*CVPixelBufferGetBytesPerRow(confidence)+x,as: UInt8.self)
            let z = base.load(fromByteOffset: y*CVPixelBufferGetBytesPerRow(buffer)+x*4,as: Float.self)
            guard quality >= 1,z.isFinite,z > 0.1,z < 4 else { return nil }
            let u = (Float(x)+0.5)*imageW/Float(w)-0.5,v = (Float(y)+0.5)*imageH/Float(h)-0.5
            let camera = SIMD4((u-k[2].x)*z/k[0].x,-(v-k[2].y)*z/k[1].y,-z,1)
            let p = m*camera
            return .init(x: Double(p.x),y: Double(p.y),z: Double(p.z))
        }
        guard let p = point(x,y),let right = point(x+normalStep,y),let down = point(x,y+normalStep),
              (right-p).length < 0.05,(down-p).length < 0.05 else { return nil }
        var normal = (right-p).cross(down-p).unit
        guard normal.length > 0.9 else { return nil }
        let camera = RadiatorPoint(x: Double(m[3].x),y: Double(m[3].y),z: Double(m[3].z))
        if normal.dot(camera-p) < 0 { normal = normal * -1 }
        return .init(point: p,normal: normal,viewpoint: viewpoint)
    }
}

private enum HouseRadiatorImageEncoder {
    static let context = CIContext(options: [.cacheIntermediates: false])
    static func jpeg(_ buffer: CVPixelBuffer) -> Data? {
        let source = CIImage(cvPixelBuffer: buffer)
        let scale = min(1,1200/max(source.extent.width,source.extent.height))
        let image = source.transformed(by: .init(scaleX: scale,y: scale))
        guard let cg = context.createCGImage(image,from: image.extent) else { return nil }
        guard let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.8), data.count <= 2 * 1024 * 1024 else { return nil }
        return data
    }
}
#endif

#if os(iOS)
/// Shows the inferred body envelope so confirmation is tied to a visible object.
struct RadiatorBodyOverlay: View {
    let scanner: HouseRadiatorScanCoordinator
    var body: some View {
        GeometryReader { proxy in
            let _ = scanner.previewRevision
            if let rect = scanner.bodyRect(in: proxy.size) {
                RoundedRectangle(cornerRadius: DS.Radius.compact).stroke(.blue,lineWidth: 2)
                    .frame(width: rect.width,height: rect.height)
                    .position(x: rect.midX,y: rect.midY)
                Text(scanner.geometry == nil ? "Radiator candidate" : "Radiator close-up")
                    .font(.caption.weight(.semibold)).padding(6).dsMaterial(in:Capsule())
                    .position(x: rect.midX,y: max(18,rect.minY-18))
            }
        }.allowsHitTesting(false)
    }
}
#endif

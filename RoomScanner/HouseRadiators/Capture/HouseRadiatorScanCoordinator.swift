#if os(iOS)
import ARKit
import AVFoundation
import CoreImage
import Observation
import RealityKit
import UIKit

/// A close-up session opened only after House capture is saved. Never changes RoomPlan's session.
@Observable @MainActor
final class HouseRadiatorScanCoordinator: NSObject,@preconcurrency ARSessionDelegate {
    let session = ARSession()
    private(set) var frontCorners: [RadiatorPoint] = []
    private(set) var geometry: RadiatorScanGeometry?
    private(set) var viewpointCount = 0
    private(set) var sampleCount = 0
    private(set) var trackingNormal = false
    private(set) var message = "Aim at the radiator body's lower-left front corner."
    private(set) var error: String?
    private(set) var frozen = false
    private(set) var photo: Data?
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
        paused = true; trackingNormal = false; session.pause()
    }
    func resume() {
        if !active { start(); return }
        guard paused,!frozen,let config = session.configuration else { return }
        paused = false; lastSampleTime = -Double.infinity
        session.run(config,options: [])
    }
    func stop() {
        generation += 1; active = false; requestingPermission = false
        session.pause()
    }
    func markCrosshair() {
        guard active,!frozen,trackingNormal,let frame = session.currentFrame,let depth = frame.sceneDepth,
              let sample = Self.sample(frame: frame,depth: depth,x: CVPixelBufferGetWidth(depth.depthMap)/2,y: CVPixelBufferGetHeight(depth.depthMap)/2,viewpoint: viewpointCount) else {
            error = "No confident depth at the crosshair. Move closer or try another angle."; return
        }
        do {
            if frontCorners.count < 3 {
                frontCorners.append(sample.point)
                message = frontCorners.count == 1 ? "Mark the lower-right front corner." : frontCorners.count == 2 ? "Mark the upper-left front corner." : "Mark the finished wall beside the radiator, not a pipe or bracket."
            } else if geometry == nil {
                geometry = try RadiatorScanGeometry(frontCorners: frontCorners,wall: sample)
                message = "Move slowly around the front, sides and top. Include the back only where it is visible."
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func resetBounds() {
        guard !frozen else { return }
        frontCorners = []; geometry = nil; points = [:]; sampleCount = 0; viewpointCount = 0
        lastCameraPosition = nil; lastCameraDirection = nil
        message = "Aim at the radiator body's lower-left front corner."; error = nil
    }
    func finish(roomID: UUID,wallID: UUID?,preset: RadiatorMountingPreset) async throws -> HouseRadiator {
        guard let geometry else { throw HouseRadiatorSurvey.Failure.incomplete }
        let samples = points.values.flatMap { $0 }
        guard samples.count >= 30,viewpointCount >= 2 else { throw HouseRadiatorSurvey.Failure.incomplete }
        frozen = true; session.pause(); trackingNormal = false
        if photo == nil,let frame = session.currentFrame {
            photo = await Task.detached(priority: .utility) {
                HouseRadiatorImageEncoder.jpeg(frame.capturedImage)
            }.value
        }
        do {
            return try geometry.result(roomID: roomID,wallID: wallID,samples: samples,viewpoints: viewpointCount,preset: preset,photo: photo)
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
        guard normal,let geometry,frame.timestamp-lastSampleTime >= 0.7,let depth = frame.sceneDepth else { return }
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

    private static func sample(frame: ARFrame,depth: ARDepthData,x: Int,y: Int,viewpoint: Int) -> RadiatorSurfaceSample? {
        CVPixelBufferLockBaseAddress(depth.depthMap,.readOnly)
        if let confidence = depth.confidenceMap { CVPixelBufferLockBaseAddress(confidence,.readOnly) }
        defer {
            CVPixelBufferUnlockBaseAddress(depth.depthMap,.readOnly)
            if let confidence = depth.confidenceMap { CVPixelBufferUnlockBaseAddress(confidence,.readOnly) }
        }
        return sampleLocked(frame: frame,depth: depth,x: x,y: y,viewpoint: viewpoint)
    }
    private static func sampleLocked(frame: ARFrame,depth: ARDepthData,x: Int,y: Int,viewpoint: Int) -> RadiatorSurfaceSample? {
        let buffer = depth.depthMap
        let w = CVPixelBufferGetWidth(buffer),h = CVPixelBufferGetHeight(buffer)
        guard x >= 0,y >= 0,x+1 < w,y+1 < h,let base = CVPixelBufferGetBaseAddress(buffer),
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
        guard let p = point(x,y),let right = point(x+1,y),let down = point(x,y+1),
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

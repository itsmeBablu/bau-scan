import XCTest
import RealityKit
import CoreGraphics
@testable import RoomScanner

final class AnnotationIconTests:XCTestCase {
    @MainActor func testMarkerHasTapVolumeAndStableIdentifier() {
        let marker = AnnotationIcon.entity(symbol:AnnotationPresentation.audioSymbol,name:"scan-note:test")
        XCTAssertEqual(marker.name,"scan-note:test")
        XCTAssertNotNil(marker.components[InputTargetComponent.self])
        XCTAssertNotNil(marker.components[BillboardComponent.self])
        XCTAssertEqual(marker.components[CollisionComponent.self]?.shapes.count,1)
    }
    @MainActor func testCameraAndWaveformTexturesHaveTransparentCornersAndReadableBackgroundDisk() throws {
        for symbol in [AnnotationPresentation.cameraSymbol,AnnotationPresentation.audioSymbol] {
            let image = try XCTUnwrap(AnnotationIcon.image(symbol))
            let width = image.width,height = image.height
            var pixels = Array(repeating:UInt8(0),count:width*height*4)
            try pixels.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(data:buffer.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
                    space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(image,in:CGRect(x:0,y:0,width:CGFloat(width),height:CGFloat(height)))
            }
            XCTAssertEqual(pixels[3],0)
            XCTAssertEqual(pixels[(width*height-1)*4+3],0)
            let opaque = stride(from:3,to:pixels.count,by:4).filter { pixels[$0] > 200 }.count
            XCTAssertGreaterThan(opaque,0)
            XCTAssertGreaterThan(opaque,width*height/2,"Evidence icons need a readable background disk")
        }
    }
    func testPlanDirectionUsesActualCameraAxesAndOmitsVerticalProjection() throws {
        var pose:[Double] = [1,0,0,0,0,1,0,0,0,0,1,0,2,3,4,1]
        XCTAssertEqual(try XCTUnwrap(AnnotationPresentation.planDirection(pose)),-Double.pi/2,accuracy:0.000001)
        pose[8] = -1; pose[10] = 0
        XCTAssertEqual(try XCTUnwrap(AnnotationPresentation.planDirection(pose)),0,accuracy:0.000001)
        pose[8] = 0; pose[9] = 1
        XCTAssertNil(AnnotationPresentation.planDirection(pose))
        XCTAssertEqual(Array(pose[12...14]),[2,3,4])
        XCTAssertEqual(AnnotationPresentation.directionCorners.count,4)
        XCTAssertTrue(AnnotationPresentation.directionCorners.allSatisfy { $0.z == -0.80 })
    }
    @MainActor func testPhotoKeepsDirectionFrustumAndVoiceUsesSurfaceLeader() throws {
        let photo = SurveyPhoto(id:UUID(),number:1,pose:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],timestamp:1)
        let camera = SurveyPhotoMarkers.entity(photo)
        XCTAssertEqual(camera.children.filter { $0.name.hasPrefix("photo-frustum-") }.count,8)
        var note = ARNote(projectID:UUID(),reference:.init(kind:.house,itemID:UUID(),library:"local"),number:1,level:0,roomID:nil,position:.init(x:1,y:1,z:1),planPosition:nil,language:"en")
        note.cameraPosition = .init(x:0,y:1.5,z:0); note.audioFileName = "note-01.m4a"; note.audioDuration = 1
        let marker = AnnotationIcon.noteEntity(note)
        XCTAssertNil(marker.findEntity(named:"capture-to-pin"),"Voice leader is drawn once")
        XCTAssertNotNil(marker.findEntity(named:"pin-label-leader"))
        let voice = try XCTUnwrap(marker.findEntity(named:"scan-note:"+note.id.uuidString))
        XCTAssertEqual(voice.position.x,0,accuracy:0.001)
        XCTAssertEqual(voice.position.y,0.28,accuracy:0.001,"Voice icon stays above the selected surface")
    }

}

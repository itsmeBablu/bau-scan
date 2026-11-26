import Foundation
import CoreGraphics
import ImageIO
@testable import RoomScanner

/// Repeatable local test data, never real capture or an accuracy reference.
struct SyntheticWorkload {
    let root: URL
    let projects: [RenovationProject]
    let entries: [ProjectLibraryEntry]
    let plans: [FloorPlan]
    static let date = Date(timeIntervalSince1970: 1_700_000_000)
    static let pose: [Double] = [1,0,0,0,0,1,0,0,0,0,1,0,2,1,3,1]

    init(root: URL, projectCount: Int = 20, scansPerProject: Int = 10) throws {
        self.root = root
        var projects: [RenovationProject] = [], entries: [ProjectLibraryEntry] = [], plans: [FloorPlan] = []
        for project in 0..<projectCount {
            var references: [ProjectReference] = []
            for scan in 0..<scansPerProject {
                let number = project * scansPerProject + scan
                var plan = FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Room \(number)")
                plan.id = Self.id(number + 1)
                let reference = ProjectReference(kind: .room, itemID: plan.id, library: "local")
                let package = root.appendingPathComponent("Rooms/\(plan.id.uuidString).roomscan")
                try RoomPackage(record: RoomRecord(plan: plan, createdAt: Self.date), plan: plan).write(to: package)
                references.append(reference); plans.append(plan)
                entries.append(.init(reference: reference, title: plan.name, date: Self.date, area: 12,
                                     roomCount: 1, root: root, url: package))
            }
            projects.append(.init(id: Self.id(10_000 + project), name: "Project \(project)", date: Self.date, references: references))
        }
        self.projects = projects; self.entries = entries; self.plans = plans
    }

    func photos(count: Int = 500) throws -> [ProjectPhotoAsset] {
        let jpeg = try Self.jpeg()
        return try (0..<count).map { index in
            let entry = entries[index % entries.count]
            let photo = SurveyPhoto(id: Self.id(20_000 + index), roomID: entry.reference.itemID,
                                    number: index / entries.count + 1, pose: Self.pose,
                                    timestamp: Double(index), capturedAt: Self.date)
            let target = entry.url.appendingPathComponent(photo.jpegPath)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try jpeg.write(to: target)
            return .init(reference: entry.reference, photo: photo, roomName: entry.title, root: entry.url, relativePath: photo.jpegPath)
        }
    }

    func audio(count: Int = 50) throws {
        // Container-header fixtures exercise storage only, not AAC decoding/playback.
        let bytes = Data([0,0,0,16]) + Data("ftypM4A ".utf8)
        for index in 0..<count {
            let project = projects[index % projects.count]
            let reference = project.references[0]
            var note = ARNote(id: Self.id(30_000 + index), projectID: project.id, reference: reference,
                              number: index / projects.count + 1, level: nil, roomID: reference.itemID,
                              position: nil, planPosition: nil, language: "en")
            note.createdAt = Self.date
            note.audioFileName = note.stem + ".m4a"; note.audioDuration = 1; note.audioModifiedAt = Self.date
            _ = try ARNoteStore.upsertAudio(note, audio: bytes, root: root)
        }
    }

    static func largeMesh(triangles: Int = 100_000) -> TriangleMesh {
        var mesh = TriangleMesh()
        for index in 0..<triangles {
            let x = Float(index % 1000), z = Float(index / 1000)
            mesh.addTriangle(.init(x,0,z), .init(x,0,z+1), .init(x+1,0,z))
        }
        return mesh
    }

    private static func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!
    }

    static func jpeg() throws -> Data {
        let width = 1024, height = 768
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0..<(width * height) {
            pixels[index * 4] = UInt8(truncatingIfNeeded: index * 17)
            pixels[index * 4 + 1] = UInt8(truncatingIfNeeded: index / width * 31)
            pixels[index * 4 + 2] = UInt8(truncatingIfNeeded: index * 7)
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw CocoaError(.fileWriteUnknown) }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }
}

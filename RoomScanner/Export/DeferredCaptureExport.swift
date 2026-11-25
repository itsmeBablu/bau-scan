import Foundation
#if canImport(RoomPlan)
import RoomPlan
import CryptoKit
#endif

/// Native RoomPlan exports are generated on demand, outside capture's peak
/// memory window. Derived files live in a cache, never in the source package.
enum DeferredCaptureExport {
    static func hasSource(_ package:URL?) -> Bool {
        #if canImport(RoomPlan)
        guard let package else { return false }
        return [FileLayout.PackageFile.capturedRoom,FileLayout.HousePackageFile.capturedStructure].contains {
            FileManager.default.fileExists(atPath:package.appendingPathComponent($0).path)
        }
        #else
        return false
        #endif
    }
    static func url(_ subject:ExportSubject,mesh:Bool) throws -> URL? {
        if let existing = mesh ? subject.usdzMeshURL : subject.usdzURL { return existing }
        #if canImport(RoomPlan)
        guard let package = subject.sourcePackageURL else { return nil }
        let name = subject.kind == .house ? FileLayout.HousePackageFile.capturedStructure : FileLayout.PackageFile.capturedRoom
        let source = package.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath:source.path) else { return nil }
        let data = try RoomPackage.coordinatedRead(at:package) { try SafePackageRead.data($0.appendingPathComponent(name),root:$0) }
        let hash = SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
        let cache = try FileManager.default.url(for:.cachesDirectory,in:.userDomainMask,appropriateFor:nil,create:true).appendingPathComponent("DeferredCaptureExports")
        let target = cache.appendingPathComponent(hash+(mesh ? "-mesh" : "-parametric")+".usdz")
        if FileManager.default.fileExists(atPath:target.path) { return target }
        let bytes:Data
        if subject.kind == .house {
            let structure = try RoomPackage.decoder.decode(CapturedStructure.self,from:data)
            bytes = try CapturedStructureAdapter.usdzData(for:structure,options:mesh ? .mesh : .parametric)
        } else {
            let room = try RoomPackage.decoder.decode(CapturedRoom.self,from:data)
            bytes = try CapturedRoomAdapter.usdzData(for:room,options:mesh ? .mesh : .parametric)
        }
        try FileManager.default.createDirectory(at:cache,withIntermediateDirectories:true)
        try bytes.write(to:target,options:.atomic)
        return target
        #else
        return nil
        #endif
    }
}

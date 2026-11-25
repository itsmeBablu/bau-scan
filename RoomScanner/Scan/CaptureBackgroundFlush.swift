#if os(iOS)
import UIKit
import Darwin

enum CaptureMemory {
    static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        let result = withUnsafeMutablePointer(to:&info) { pointer in
            pointer.withMemoryRebound(to:integer_t.self,capacity:Int(count)) { task_info(mach_task_self_,task_flavor_t(MACH_TASK_BASIC_INFO),$0,&count) }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }
}
@MainActor enum CaptureBackgroundFlush {
    static func run(_ operation:() async -> Void) async {
        var token = UIBackgroundTaskIdentifier.invalid
        token = UIApplication.shared.beginBackgroundTask(withName:"Scan checkpoint") {
            if token != .invalid { UIApplication.shared.endBackgroundTask(token); token = .invalid }
        }
        await operation()
        if token != .invalid { UIApplication.shared.endBackgroundTask(token) }
    }
}
#endif

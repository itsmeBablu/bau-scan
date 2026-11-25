#if canImport(RoomPlan)
import RoomPlan

/// Keeps RoomCaptureView's coaching/finalization delegate and observes snapshots.
final class RoomCheckpointObserver: RoomCaptureSessionDelegate {
    weak var forward: (any RoomCaptureSessionDelegate)?
    var onUpdate: ((CapturedRoom)->Void)?
    func captureSession(_ session:RoomCaptureSession,didUpdate room:CapturedRoom) { forward?.captureSession(session,didUpdate:room); onUpdate?(room) }
    func captureSession(_ session:RoomCaptureSession,didAdd room:CapturedRoom) { forward?.captureSession(session,didAdd:room); onUpdate?(room) }
    func captureSession(_ session:RoomCaptureSession,didChange room:CapturedRoom) { forward?.captureSession(session,didChange:room); onUpdate?(room) }
    func captureSession(_ session:RoomCaptureSession,didRemove room:CapturedRoom) { forward?.captureSession(session,didRemove:room); onUpdate?(room) }
    func captureSession(_ session:RoomCaptureSession,didProvide instruction:RoomCaptureSession.Instruction) { forward?.captureSession(session,didProvide:instruction) }
    func captureSession(_ session:RoomCaptureSession,didStartWith configuration:RoomCaptureSession.Configuration) { forward?.captureSession(session,didStartWith:configuration) }
    func captureSession(_ session:RoomCaptureSession,didEndWith data:CapturedRoomData,error:(any Error)?) { forward?.captureSession(session,didEndWith:data,error:error) }
}
#endif

#if canImport(RoomPlan)
import SwiftUI
import RoomPlan

/// Hosts UIKit `RoomCaptureView` inside SwiftUI.
struct RoomCaptureViewRepresentable: UIViewRepresentable {
    let coordinator: ScanCoordinator

    func makeUIView(context: Context) -> RoomCaptureView { coordinator.captureView }
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}
#endif

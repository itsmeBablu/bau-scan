#if canImport(RoomPlan)
import SwiftUI
import RoomPlan

/// Hosts UIKit `RoomCaptureView` inside SwiftUI.
struct RoomCaptureViewRepresentable: UIViewControllerRepresentable {
    let coordinator: ScanCoordinator

    func makeUIViewController(context: Context) -> CaptureHostController {
        CaptureHostController(coordinator: coordinator)
    }
    func updateUIViewController(_ controller: CaptureHostController, context: Context) {}

    static func dismantleUIViewController(_ controller: CaptureHostController, coordinator: ()) {
        controller.scanner.stop()
    }
}

/// Start capture after UIKit has sized and displayed the camera view, rather than
/// during the earlier SwiftUI appearance callback or a button's state mutation.
final class CaptureHostController: UIViewController {
    let scanner: ScanCoordinator

    init(coordinator: ScanCoordinator) {
        scanner = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let container = UIView()
        container.backgroundColor = .black
        let camera = scanner.captureView
        camera.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(camera)
        NSLayoutConstraint.activate([
            camera.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            camera.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            camera.topAnchor.constraint(equalTo: container.topAnchor),
            camera.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        view = container
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scanner.start()
    }
}
#endif

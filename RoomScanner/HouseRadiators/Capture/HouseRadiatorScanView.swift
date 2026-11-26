#if os(iOS)
import SwiftUI
import RealityKit
import AVFoundation

struct HouseRadiatorScanView: View {
    let roomID: UUID
    let wallID: UUID?
    let save: (HouseRadiator) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var scanner = HouseRadiatorScanCoordinator()
    @State private var preset = RadiatorMountingPreset.none
    @State private var busy = false
    @State private var error: String?
    @State private var result: HouseRadiator?
    @State private var confirmDiscard = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let result { HouseRadiatorPreview(radiator: result).frame(minHeight: 180) }
                else {
                    RadiatorCamera(scanner: scanner)
                        .overlay { RadiatorBodyOverlay(scanner: scanner) }
                        .frame(minHeight: 180,maxHeight: .infinity)
                }
                Form {
                    Section("Radiator close-up") {
                        if let result {
                            Text("Review before saving. Width and height use the automatically proposed visible body envelope; scan-derived sizes remain estimates.").font(.caption)
                            RadiatorDimensionRows(radiator: result)
                        } else {
                            Text(scanner.message).font(.callout)
                            Text("Keep the full radiator and adjacent wall visible. Confirm the detected candidate, then move closer around its sides. Geometry proposals can match other equipment.").font(.caption).foregroundStyle(.secondary)
                            if scanner.geometry == nil {
                                if let candidate = scanner.candidate {
                                    Text("Candidate: \(candidate.geometry.width, specifier: "%.2f") × \(candidate.geometry.height, specifier: "%.2f") m")
                                    Button("This is a radiator · measure closer") { scanner.acceptCandidate() }
                                        .dsProminentControl().disabled(!scanner.trackingNormal)
                                    Button("Not a radiator") { scanner.skipCandidate() }
                                }
                            } else {
                                Text("\(scanner.viewpointCount) viewpoints · \(scanner.sampleCount) surface samples")
                                Button("Finish radiator scan") { finish() }
                                    .dsProminentControl().disabled(busy || scanner.sampleCount < 30 || scanner.viewpointCount < 2)
                            }
                            Button("Find another candidate") { scanner.resetBounds() }.disabled(scanner.geometry == nil && scanner.candidate == nil)
                        }
                        if let failure = error ?? scanner.error {
                            Text(failure).foregroundStyle(DS.ColorToken.error.color)
                            if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                                Button("Camera settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                            }
                        }
                        if busy { ProgressView(result == nil ? "Processing scan…" : "Saving radiator…") }
                    }
                    if result == nil {
                        Section("When the rear face is hidden") {
                            Picker("Mounting gap fallback",selection: $preset) {
                                ForEach(RadiatorMountingPreset.allCases,id: \.self) { Text($0.title).tag($0) }
                            }
                            Text("No assumption is applied by default. KERMI examples apply only to the selected long wall console; they are not a universal German/DIN mounting rule. A scan-supported rear face takes priority.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.formStyle(.grouped).frame(maxHeight: 340)
            }
            .navigationTitle("Scan radiator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") {
                    if scanner.frontCorners.isEmpty { scanner.stop(); dismiss() } else { confirmDiscard = true }
                }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { persist() }.disabled(result == nil || busy) }
            }
            .disabled(busy)
        }
        .interactiveDismissDisabled(!scanner.frontCorners.isEmpty || busy)
        .confirmationDialog("Discard this unsaved radiator scan?",isPresented: $confirmDiscard,titleVisibility: .visible) {
            Button("Discard",role: .destructive) { scanner.stop(); dismiss() }
        }
        .onDisappear { scanner.stop() }
        .onChange(of: phase) { _, phase in if phase == .active { scanner.resume() } else { scanner.pause() } }
    }
    private func finish() {
        guard !busy else { return }; busy = true; error = nil
        Task { @MainActor in
            defer { busy = false }
            do { result = try await scanner.finish(roomID: roomID,wallID: wallID,preset: preset) }
            catch { self.error = error.localizedDescription }
        }
    }
    private func persist() {
        guard let result,!busy else { return }; busy = true; error = nil
        Task { @MainActor in
            defer { busy = false }
            do { try await save(result); scanner.stop(); dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct RadiatorCamera: UIViewControllerRepresentable {
    let scanner: HouseRadiatorScanCoordinator
    func makeUIViewController(context: Context) -> RadiatorCameraHost { .init(scanner: scanner) }
    func updateUIViewController(_ controller: RadiatorCameraHost,context: Context) {}
    static func dismantleUIViewController(_ controller: RadiatorCameraHost,coordinator: ()) { controller.scanner.stop() }
}
private final class RadiatorCameraHost: UIViewController {
    let scanner: HouseRadiatorScanCoordinator
    private let camera = ARView(frame: .zero,cameraMode: .ar,automaticallyConfigureSession: false)
    init(scanner: HouseRadiatorScanCoordinator) { self.scanner = scanner; super.init(nibName: nil,bundle: nil); camera.session = scanner.session; camera.environment.background = .cameraFeed() }
    required init?(coder: NSCoder) { nil }
    override func loadView() { view = camera }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); scanner.start() }
}
#endif

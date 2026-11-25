#if os(iOS)
import SwiftUI
import RealityKit
import ARKit

/// Read-only prototype. Normal tracking is a relocalization candidate, never
/// permission to merge newly captured rooms into a recovered coordinate frame.
struct ScanRelocalizationProbe: View {
    let session: ScanSession
    let store: ScanSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var map: Data?
    @State private var status = AppLanguage.text("Loading saved world map…")
    var body: some View {
        NavigationStack {
            ZStack(alignment:.bottom) {
                if let map { RelocalizationCamera(map:map,status:$status).ignoresSafeArea() }
                else { Color.black.ignoresSafeArea() }
                Text(status).padding().background(.regularMaterial,in:RoundedRectangle(cornerRadius:16)).padding()
            }.navigationTitle("Alignment prototype")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
        }.task {
            do {
                guard let value = try await store.latestValues(session.id,prefix:"world-map").last else { status = AppLanguage.text("No saved world map. New rooms remain unaligned."); return }
                map = try JSONDecoder().decode(Data.self,from:value.data)
            } catch { status = error.localizedDescription }
        }
    }
}
private struct RelocalizationCamera: UIViewRepresentable {
    let map: Data
    @Binding var status: String
    func makeCoordinator() -> Coordinator { Coordinator(status:$status) }
    func makeUIView(context:Context) -> ARView {
        let view = ARView(frame:.zero,cameraMode:.ar,automaticallyConfigureSession:false)
        view.session.delegate = context.coordinator
        do {
            guard ARWorldTrackingConfiguration.isSupported,
                  let world = try NSKeyedUnarchiver.unarchivedObject(ofClass:ARWorldMap.self,from:map) else { throw CocoaError(.featureUnsupported) }
            let configuration = ARWorldTrackingConfiguration(); configuration.initialWorldMap = world
            view.session.run(configuration,options:[.resetTracking,.removeExistingAnchors])
            context.coordinator.timeout = Task { @MainActor in
                try? await Task.sleep(for:.seconds(20))
                guard !Task.isCancelled,!context.coordinator.candidate else { return }
                status = AppLanguage.text("Relocalization not established. New rooms remain unaligned.")
            }
        } catch { DispatchQueue.main.async { status = error.localizedDescription } }
        return view
    }
    func updateUIView(_ view:ARView,context:Context) {}
    static func dismantleUIView(_ view:ARView,coordinator:Coordinator) { coordinator.timeout?.cancel(); view.session.pause() }
    @MainActor final class Coordinator:NSObject,@preconcurrency ARSessionDelegate {
        @Binding var status:String
        var timeout:Task<Void,Never>?
        var candidate = false
        init(status:Binding<String>) { _status = status }
        func session(_ session:ARSession,didUpdate frame:ARFrame) {
            guard !candidate,frame.camera.trackingState == .normal,frame.worldMappingStatus == .mapped else { return }
            candidate = true
            status = AppLanguage.text("Tracking recovered. Verify a known checkpoint before merging. No new rooms are merged by this prototype.")
        }
        func session(_ session:ARSession,didFailWithError error:Error) { status = error.localizedDescription }
    }
}
#endif

#if canImport(RoomPlan)
import SwiftUI

/// Dedicated single-room workflow. House capture and house packages are independent.
struct TechnicalRoomScanView: View {
    @Environment(RoomStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator = ScanCoordinator(mode: .room)
    @State private var started = false
    @State private var active = true
    @State private var notes = ""
    @State private var errorMessage: String?
    let onSaved: (LibraryItem) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if !started {
                    Form {
                        Section("One Technik Room") {
                            Text("Scan one room slowly. Cover the walls, floor and ceiling, then revisit visible equipment from several angles before finishing.")
                            Text("RoomPlan captures the room shell and supported objects. Pipe diameters, connections and equipment details need manual verification.")
                                .foregroundStyle(.secondary)
                        }
                        Section("Room notes") {
                            TextField("Equipment, access or survey notes", text: $notes, axis: .vertical)
                        }
                        Button("Start single-room scan") { started = true }
                            .disabled(!ScanCoordinator.isSupported)
                    }
                } else {
                    capture
                }
            }
            .navigationTitle("Technik Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { active = false; coordinator.cancel(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if started {
                        Button("Finish room") { coordinator.finish() }
                            .disabled(coordinator.state != .scanning)
                    }
                }
            }
        }
        .onChange(of: coordinator.state) { _, state in receive(state) }
        .onDisappear { active = false; coordinator.stop() }
        .alert("Technik Room", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { dismiss() }
        } message: { Text(errorMessage ?? "") }
    }

    @ViewBuilder private var capture: some View {
        switch coordinator.state {
        case .failed(.cameraDenied): CameraDeniedView(onClose: { dismiss() })
        case .failed(.unsupportedDevice): UnsupportedDeviceView(onClose: { dismiss() })
        default:
            RoomCaptureViewRepresentable(coordinator: coordinator)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if coordinator.state == .processing {
                        ProgressView("Preparing room…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
        }
    }

    private func receive(_ state: ScanCoordinator.State) {
        guard active else { return }
        switch state {
        case .finished(let result):
            do {
                let existing = Set(store.records.map(\.name))
                var name = "Technik Room"
                var index = 2
                while existing.contains(name) { name = "Technik Room \(index)"; index += 1 }
                let plan = FloorPlanBuilder().build(from: result.scan, name: name)
                let technical = TechnicalRoom.capturedShell(id: plan.id, notes: notes)
                let package = RoomPackage(record: RoomRecord(plan: plan), plan: plan, scan: result.scan,
                    capturedRoomData: result.capturedRoomData, usdzData: result.usdzData, usdzMeshData: result.usdzMeshData,
                    thumbnailPNG: PlanRenderer.thumbnailPNG(for: plan), technicalRoomData: try TechnicalRoomJSONExporter.data(for: technical))
                let record = try store.save(package)
                active = false
                onSaved(.room(record))
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        case .failed(let error) where error != .scanCancelled && error != .cameraDenied && error != .unsupportedDevice:
            errorMessage = error.localizedDescription
        default: break
        }
    }
}
#endif

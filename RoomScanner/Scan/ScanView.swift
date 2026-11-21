#if canImport(RoomPlan)
import SwiftUI

/// Full-screen scan view: guidance, Cancel / Done, processing,
/// saving to `RoomStore` and returning to library.
/// House mode: one uninterrupted capture until Finish House, then a `.housescan` package.
struct ScanView: View {
    @Environment(RoomStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator: ScanCoordinator
    @State private var saveError: AppError?
    @State private var radiatorScanner: HouseRadiatorScanCoordinator?
    @State private var radiators: [HouseRadiator] = []
    @State private var radiatorBusy = false
    @State private var radiatorError: String?
    @State private var mountingPreset = RadiatorMountingPreset.none
    @Environment(\.scenePhase) private var scenePhase
    let mode: ScanMode
    /// Created item (room or house) passed to caller to display.
    var onSaved: (LibraryItem) -> Void

    init(mode: ScanMode = .room, onSaved: @escaping (LibraryItem) -> Void = { _ in }) {
        self.mode = mode
        self.onSaved = onSaved
        _coordinator = State(initialValue: ScanCoordinator(mode: mode))
    }

    var body: some View {
        ZStack {
            switch coordinator.state {
            case .failed(.cameraDenied):
                CameraDeniedView(onClose: { dismiss() })
            case .failed(.unsupportedDevice):
                UnsupportedDeviceView(onClose: { dismiss() })
            default:
                RoomCaptureViewRepresentable(coordinator: coordinator)
                    .ignoresSafeArea()
                    .overlay {
                        if radiatorScanner != nil {
                            Image(systemName: "plus").foregroundStyle(.white).shadow(color: .black,radius: 1)
                                .allowsHitTesting(false)
                        }
                    }
                overlay
            }
        }
        .onDisappear { coordinator.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { radiatorScanner?.resume() } else { radiatorScanner?.pause() }
        }
        .task(id: radiatorScanner != nil) {
            while !Task.isCancelled,radiatorScanner != nil {
                radiatorScanner?.refreshSharedFrame()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        .onChange(of: coordinator.state) { _, state in handle(state) }
        .alert(item: $saveError) { error in
            Alert(title: Text("scan.error.title"), message: Text(error.localizedDescription),
                  dismissButton: .default(Text("common.ok")) { dismiss() })
        }
    }

    @ViewBuilder private var overlay: some View {
        VStack {
            HStack {
                Button(role: .cancel) { coordinator.cancel(); dismiss() } label: { Text("common.cancel") }
                    .buttonStyle(.bordered)
                Spacer()
                if mode == .house {
                    Text("House scan")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                    Spacer()
                }
                Button { coordinator.finish() } label: { Text(mode == .house ? "scan.finishHouse" : "scan.finish") }
                    .buttonStyle(.borderedProminent)
                    .disabled(coordinator.state != .scanning || radiatorScanner != nil)
            }
            .padding()
            Spacer()
            if mode == .house,coordinator.state == .scanning {
                if let scanner = radiatorScanner {
                    radiatorControls(scanner)
                } else {
                    Button {
                        let scanner = HouseRadiatorScanCoordinator(session: coordinator.arSession)
                        radiatorScanner = scanner; radiatorError = nil
                        mountingPreset = .none; scanner.start()
                    } label: { Label("Capture radiator · \(radiators.count) saved in this scan",systemImage: "heater.vertical") }
                    .buttonStyle(.borderedProminent)
                    .disabled(radiators.reduce(0) { $0+$1.samples.count } > 142_000)
                    .padding(.bottom,32)
                }
            }
        }
        switch coordinator.state {
        case .processing, .merging:
            VStack(spacing: 12) {
                ProgressView()
                Text(coordinator.state == .merging ? "scan.merging" : "scan.processing")
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        default:
            EmptyView()
        }
    }

    private func radiatorControls(_ scanner: HouseRadiatorScanCoordinator) -> some View {
        ScrollView {
          VStack(alignment: .leading,spacing: 8) {
            Text("Radiator · Heizkörper").font(.headline)
            Text(scanner.message).font(.callout)
            Text("Identify the radiator by marking its front body corners, then the adjacent wall. House capture continues.").font(.caption)
            if !scanner.depthAvailable {
                Text("Waiting for camera depth. Aim at the radiator from 0.5–2 m away. If depth remains unavailable, continue the House and use its Radiators option afterwards.").font(.caption).foregroundStyle(.orange)
            }
            if let error = radiatorError ?? scanner.error { Text(error).font(.caption).foregroundStyle(.red) }
            if scanner.geometry == nil {
                Button(scanner.frontCorners.count < 3 ? "Mark front corner \(scanner.frontCorners.count+1)" : "Mark adjacent wall") { scanner.markCrosshair() }
                    .buttonStyle(.borderedProminent).disabled(!scanner.trackingNormal || !scanner.depthAvailable || radiatorBusy)
            } else {
                Text("\(scanner.viewpointCount) viewpoints · \(scanner.sampleCount) surface samples").font(.caption).monospacedDigit()
                Picker("Hidden rear gap",selection: $mountingPreset) {
                    ForEach(RadiatorMountingPreset.allCases,id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.menu)
                Button("Save radiator and continue House") { saveRadiator(scanner) }
                    .buttonStyle(.borderedProminent).disabled(radiatorBusy || scanner.sampleCount < 30 || scanner.viewpointCount < 2)
            }
            HStack {
                Button("Reset corners") { scanner.resetBounds(); radiatorError = nil }.disabled(radiatorBusy)
                Spacer()
                Button("Discard radiator",role: .destructive) { scanner.stop(); radiatorScanner = nil }.disabled(radiatorBusy)
            }.font(.callout)
            if radiatorBusy { ProgressView("Processing radiator…") }
          }.padding()
        }
        .frame(maxHeight: 260)
        .background(.regularMaterial,in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    private func saveRadiator(_ scanner: HouseRadiatorScanCoordinator) {
        guard !radiatorBusy else { return }
        radiatorBusy = true; radiatorError = nil
        Task { @MainActor in
            defer { radiatorBusy = false }
            do {
                var item = try await scanner.finish(roomID: UUID(),wallID: nil,preset: mountingPreset)
                item.name = "Radiator \(radiators.count+1)"; item.capturedInHouseCoordinates = true
                if radiators.reduce(0,{ $0+($1.photoJPEG?.count ?? 0) })+(item.photoJPEG?.count ?? 0) > 24*1_048_576 { item.photoJPEG = nil }
                radiators.append(item); scanner.stop(); radiatorScanner = nil
            } catch { radiatorError = error.localizedDescription }
        }
    }

    private func handle(_ state: ScanCoordinator.State) {
        switch state {
        case .finished(let result):
            do {
                let name = store.proposedName(for: result.scan.sectionLabels.first ?? .unidentified)
                let plan = FloorPlanBuilder().build(from: result.scan, name: name)
                let package = RoomPackage(record: RoomRecord(plan: plan), plan: plan, scan: result.scan,
                                          capturedRoomData: result.capturedRoomData, usdzData: result.usdzData, usdzMeshData: result.usdzMeshData,
                                          thumbnailPNG: PlanRenderer.thumbnailPNG(for: plan))
                let record = try store.save(package)
                onSaved(.room(record))
                dismiss()
            } catch {
                saveError = .storageFailed(error.localizedDescription)
            }
        case .finishedHouse(let result):
            do {
                let extras = result.rooms.mapValues { HousePackage.RoomExtras(capturedRoomData: $0.capturedRoomData, usdzData: $0.usdzData, usdzMeshData: $0.usdzMeshData) }
                var package = HousePackage.assemble(structure: result.structure, name: store.proposedHouseName(),
                                                    capturedStructureData: result.capturedStructureData, usdzData: result.usdzData, roomExtras: extras)
                if !radiators.isEmpty {
                    package.radiators = try HouseRadiatorRegistration.associate(radiators,house: package.house,structure: result.structure)
                }
                let record = try store.saveHouse(package)
                onSaved(.house(record))
                dismiss()
            } catch {
                saveError = .storageFailed(error.localizedDescription)
            }
        case .failed(let error) where error != .scanCancelled && error != .cameraDenied && error != .unsupportedDevice:
            saveError = error
        default:
            break
        }
    }
}

extension AppError: Identifiable {
    var id: String { localizedDescription }
}
#endif

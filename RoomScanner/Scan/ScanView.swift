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
    @State private var automaticRadiators = true
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
                        if let scanner = radiatorScanner { RadiatorBodyOverlay(scanner: scanner) }
                    }
                overlay
            }
        }
        .onDisappear { radiatorScanner?.stop(); coordinator.stop() }
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
                    .disabled(coordinator.state != .scanning || radiatorScanner?.geometry != nil || radiatorBusy)
            }
            .padding()
            Spacer()
            if mode == .house,coordinator.state == .scanning {
                if let scanner = radiatorScanner {
                    radiatorControls(scanner)
                } else {
                    Button { automaticRadiators = true; startAutomaticRadiators() } label: {
                        Label("Detect radiators",systemImage: "heater.vertical")
                    }.buttonStyle(.bordered).disabled(!radiatorBudgetAvailable).padding(.bottom,32)
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
            Text("Radiator · Heizkörper · \(radiators.count) saved").font(.headline)
            Text(scanner.message).font(.callout)
            Text("Automatic geometry proposals · confirm the equipment type. No corner marking. House capture continues.").font(.caption)
            if !scanner.depthAvailable {
                Text("Waiting for camera depth. Aim at the radiator from 0.5–2 m away. If depth remains unavailable, continue the House and use its Radiators option afterwards.").font(.caption).foregroundStyle(.orange)
            }
            if let error = radiatorError ?? scanner.error { Text(error).font(.caption).foregroundStyle(.red) }
            if scanner.geometry == nil {
                if let candidate = scanner.candidate {
                    Text("Visible body: \(candidate.geometry.width, specifier: "%.2f") × \(candidate.geometry.height, specifier: "%.2f") m · scan estimate").font(.caption)
                    Button("This is a radiator · measure closer") { scanner.acceptCandidate() }
                        .buttonStyle(.borderedProminent).disabled(!scanner.trackingNormal || radiatorBusy)
                    Button("Not a radiator") { scanner.skipCandidate() }
                } else {
                    Text("Keep the whole radiator and nearby wall in view, then move closer after confirming a candidate.").font(.caption)
                }
            } else {
                if let body = scanner.geometry {
                    Text("Body: \(body.width, specifier: "%.2f") × \(body.height, specifier: "%.2f") m · wall to front: \(body.wallToFront, specifier: "%.2f") m").font(.caption)
                }
                Text("\(scanner.viewpointCount) viewpoints · \(scanner.sampleCount) surface samples").font(.caption).monospacedDigit()
                Picker("Hidden rear gap",selection: $mountingPreset) {
                    ForEach(RadiatorMountingPreset.allCases,id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.menu)
                Button("Save radiator and continue House") { saveRadiator(scanner) }
                    .buttonStyle(.borderedProminent).disabled(radiatorBusy || scanner.sampleCount < 30 || scanner.viewpointCount < 2)
            }
            HStack {
                Button("Find another candidate") { scanner.resetBounds(); radiatorError = nil }.disabled(radiatorBusy)
                Spacer()
                Button(scanner.geometry == nil ? "Pause detection" : "Discard measurement") {
                    if scanner.geometry != nil { scanner.skipCandidate() }
                    else { scanner.stop(); radiatorScanner = nil; automaticRadiators = false }
                }.disabled(radiatorBusy)
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
        guard radiators.count < 100,radiators.reduce(0,{ $0+$1.samples.count })+scanner.sampleCount <= 150_000 else {
            radiatorError = "Radiator evidence limit reached. Finish the House, then record additional observations separately."; return
        }
        radiatorBusy = true; radiatorError = nil
        Task { @MainActor in
            defer { radiatorBusy = false }
            do {
                var item = try await scanner.finish(roomID: UUID(),wallID: nil,preset: mountingPreset)
                item.name = "Radiator \(radiators.count+1)"; item.capturedInHouseCoordinates = true
                if radiators.reduce(0,{ $0+($1.photoJPEG?.count ?? 0) })+(item.photoJPEG?.count ?? 0) > 24*1_048_576 { item.photoJPEG = nil }
                radiators.append(item); scanner.skipCandidate(); mountingPreset = .none
                if !radiatorBudgetAvailable { scanner.stop(); radiatorScanner = nil }
            } catch { radiatorError = error.localizedDescription }
        }
    }

    private var radiatorBudgetAvailable: Bool {
        radiators.count < 100 && radiators.reduce(0,{ $0+$1.samples.count }) <= 142_000
    }
    private func startAutomaticRadiators() {
        guard radiatorBudgetAvailable,mode == .house,automaticRadiators,radiatorScanner == nil,coordinator.state == .scanning else { return }
        let scanner = HouseRadiatorScanCoordinator(session: coordinator.arSession)
        radiatorScanner = scanner; scanner.start()
    }

    private func handle(_ state: ScanCoordinator.State) {
        switch state {
        case .scanning:
            startAutomaticRadiators()
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

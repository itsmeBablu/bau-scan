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
    @State private var photoCapture = HouseSurveyPhotoCapture()
    @State private var cameraLive = false
    @AppStorage(ScanPhotoPolicy.preferenceKey) private var cameraPhotos = true
    @Environment(\.scenePhase) private var scenePhase
    private let workspace: RenovationWorkspace?
    @State private var persistence: CapturePersistence
    private var captureID: UUID { persistence.id }
    @State private var showingVoiceNotes = false
    let voiceProjectID: UUID?
    let mode: ScanMode
    /// Created item (room or house) passed to caller to display.
    var onSaved: (LibraryItem) -> Void

    init(mode: ScanMode = .room, voiceProjectID: UUID? = nil, workspace: RenovationWorkspace? = nil, onSaved: @escaping (LibraryItem) -> Void = { _ in }) {
        self.workspace = workspace
        self.voiceProjectID = voiceProjectID
        self.mode = mode
        self.onSaved = onSaved
        let disk = CapturePersistence(kind:mode == .house ? .house : .room,projectID:voiceProjectID)
        _persistence = State(initialValue:disk)
        let scanner = ScanCoordinator(mode:mode); scanner.persistence = disk
        _coordinator = State(initialValue:scanner)
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

                overlay
            }
        }
        .sheet(isPresented:$showingVoiceNotes) {
            if let voiceProjectID,let workspace {
                NavigationStack {
                    ProjectVoiceNotesView(projectID:voiceProjectID,initialReference:captureReference,onClose:{ showingVoiceNotes = false }).environment(workspace)
                }
            }
        }
        .onDisappear { radiatorScanner?.stop(); coordinator.stop() }
        .modifier(ScanPhotoFeedback(count:photoCapture.completed))
        .overlay(alignment:.bottomTrailing) {
            if ScanPhotoPolicy.buttonVisible(enabled:cameraPhotos,cameraRunning:cameraLive) {
                ScanPhotoButton(busy:photoCapture.busy) { Task { await photoCapture.capture(session:coordinator.arSession) } }.padding(20)
            }
        }
        .alert("Survey photo",isPresented:Binding(get:{ photoCapture.error != nil },set:{ if !$0 { photoCapture.error = nil } })) {
            Button("OK") { photoCapture.error = nil }
        } message: { Text(photoCapture.error ?? "") }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if coordinator.state == .failed(.cameraDenied) { coordinator.start() }
                radiatorScanner?.resume()
            } else {
                radiatorScanner?.pause()
                Task { await CaptureBackgroundFlush.run { await coordinator.flushAndPause(.background) } }
            }
        }
        .task(id:coordinator.state == .scanning) {
            cameraLive = false
            while !Task.isCancelled,coordinator.state == .scanning {
                cameraLive = scenePhase == .active && coordinator.arSession.currentFrame?.camera.trackingState == .normal
                try? await Task.sleep(for:.milliseconds(250))
            }
            cameraLive = false
        }
        .task(id: radiatorScanner != nil) {
            while !Task.isCancelled,radiatorScanner != nil {
                radiatorScanner?.refreshSharedFrame()
                if let scanner = radiatorScanner,!radiatorBusy,scanner.geometry != nil,scanner.sampleCount >= 120,scanner.viewpointCount >= 3 {
                    await saveRadiator(scanner)
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for:UIApplication.didReceiveMemoryWarningNotification)) { _ in coordinator.flushCheckpoint(.memoryWarning) }
        .onChange(of: coordinator.state) { _, state in handle(state) }
        .alert(item: $saveError) { error in
            Alert(title: Text("scan.error.title"), message: Text(error.localizedDescription),
                  dismissButton: .default(Text("common.ok")))
        }
    }

    @ViewBuilder private var overlay: some View {
        if mode == .house,let scanner = radiatorScanner {
            GeometryReader { geometry in
                let _ = scanner.previewRevision
                ForEach(Array(radiators.suffix(12))) { radiator in
                    if let rect = scanner.bodyRect(for: radiator,in: geometry.size) {
                        RoundedRectangle(cornerRadius: 6).stroke(.green,lineWidth: 2)
                            .frame(width: rect.width,height: rect.height).position(x: rect.midX,y: rect.midY)
                    }
                }
                if let rect = scanner.bodyRect(in: geometry.size) {
                    ZStack {
                    RoundedRectangle(cornerRadius: 6).stroke(.cyan,lineWidth: 3)
                        .frame(width: rect.width,height: rect.height).position(x: rect.midX,y: rect.midY)
                    Text("Radiator candidate").font(.caption.bold()).padding(6).background(.regularMaterial,in: Capsule()).position(x: rect.midX,y: max(90,rect.minY-18))
                    }
                }
            }.ignoresSafeArea().allowsHitTesting(false)
        }
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
                Button { Task { await finishScan() } } label: { Text(mode == .house ? "scan.finishHouse" : "scan.finish") }
                    .buttonStyle(.borderedProminent)
                    .disabled((coordinator.state != .scanning && coordinator.state != .roomSaved) || radiatorBusy || photoCapture.busy)
            }
            .padding()
            Spacer()
            if case .failed = coordinator.state,mode == .house {
                Button("Retry finishing") { coordinator.retryFinish() }.buttonStyle(.borderedProminent)
            }
            if let diagnostic = coordinator.cameraDiagnostic {
                Text(diagnostic).font(.callout).padding().background(.regularMaterial,in:RoundedRectangle(cornerRadius:12))
            }
            VStack(spacing:8) {
                ScanSaveStatus(persistence:persistence)
                if mode == .house {
                    HStack {
                        Button("Room done") { coordinator.roomDone() }.disabled(coordinator.state != .scanning)
                        Button("Next room") { coordinator.nextRoom() }.disabled(coordinator.state != .roomSaved)
                    }.buttonStyle(.borderedProminent)
                }
            }.padding(.bottom,8)
            HStack {
                if voiceProjectID != nil,let workspace {
                    Button {
                        if let voiceProjectID { workspace.change { index in index.reconcile([captureReference]); try index.assign(captureReference,to:voiceProjectID) } }
                        guard workspace.error == nil else { return }
                        showingVoiceNotes = true
                    } label: { Label("Voice note",systemImage:"mic.fill").padding(12) }
                        .background(.regularMaterial,in:Capsule())
                        .disabled(coordinator.state != .scanning)
                }
                Spacer()
            }.padding(.horizontal,20).padding(.bottom,20)

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

    private var captureReference: ProjectReference {
        .init(kind:mode == .house ? .house : .room,itemID:captureID,library:store.isCloud ? "icloud" : "local")
    }

    private func finishScan() async {
        guard !radiatorBusy else { return }
        if let scanner = radiatorScanner,scanner.geometry != nil,scanner.sampleCount >= 120,scanner.viewpointCount >= 3 {
            await saveRadiator(scanner)
        }
        radiatorScanner?.stop(); radiatorScanner = nil
        coordinator.finish()
    }
    private func saveRadiator(_ scanner: HouseRadiatorScanCoordinator) async {
        guard !radiatorBusy else { return }
        guard radiators.count < 100,radiators.reduce(0,{ $0+$1.samples.count })+scanner.sampleCount <= 150_000 else {
            scanner.stop(); radiatorScanner = nil; return
        }
        radiatorBusy = true
        defer { radiatorBusy = false }
        do {
            var item = try await scanner.finish(roomID: UUID(),wallID: nil,preset: .none)
            item.name = "Possible radiator \(radiators.count+1)"; item.capturedInHouseCoordinates = true
            if radiators.reduce(0,{ $0+($1.photoJPEG?.count ?? 0) })+(item.photoJPEG?.count ?? 0) > 24*1_048_576 { item.photoJPEG = nil }
            radiators.append(item); scanner.skipCandidate()
            if !radiatorBudgetAvailable { scanner.stop(); radiatorScanner = nil }
        } catch {
            // Failed proposals are discarded rather than repeatedly freezing House capture.
            scanner.skipCandidate()
        }
    }

    private var radiatorBudgetAvailable: Bool {
        radiators.count < 100 && radiators.reduce(0,{ $0+$1.samples.count }) <= 142_000
    }
    private func startAutomaticRadiators() {
        guard coordinator.detectsRadiators,radiatorBudgetAvailable,radiatorScanner == nil,coordinator.state == .scanning else { return }
        let scanner = HouseRadiatorScanCoordinator(session: coordinator.arSession,automaticCapture: true)
        radiatorScanner = scanner; scanner.start()
    }

    private func handle(_ state: ScanCoordinator.State) {
        switch state {
        case .scanning:
            startAutomaticRadiators()
        case .finished(let result):
            do {
                let name = store.proposedName(for: result.scan.sectionLabels.first ?? .unidentified)
                var plan = FloorPlanBuilder().build(from: result.scan, name: name)
                plan.id = captureID
                var package = RoomPackage(record: RoomRecord(plan: plan), plan: plan, scan: result.scan,
                                          capturedRoomData: result.capturedRoomData, usdzData: result.usdzData, usdzMeshData: result.usdzMeshData,
                                          thumbnailPNG: PlanRenderer.thumbnailPNG(for: plan))
                package.surveyPhotos = photoCapture.registered(house:House(room:plan),scans:[result.scan],alignSingleRoom:true)
                package.surveyPhotoAssets = photoCapture.assets
                let record = try store.save(package)
                Task { await persistence.complete() }
                onSaved(.room(record))
                dismiss()
            } catch {
                saveError = .storageFailed(error.localizedDescription)
            }
        case .finishedHouse(let result):
            do {
                let extras = result.rooms.mapValues { HousePackage.RoomExtras(capturedRoomData: $0.capturedRoomData, usdzData: $0.usdzData, usdzMeshData: $0.usdzMeshData) }
                var package = try HousePackage.assemble(structure: result.structure, name: store.proposedHouseName(),
                                                    capturedStructureData: result.capturedStructureData, usdzData: result.usdzData, roomExtras: extras)
                package.house.id = captureID
                package.record.id = captureID
                package.structure?.id = captureID
                if !radiators.isEmpty {
                    package.radiators = try HouseRadiatorRegistration.associate(radiators,house: package.house,structure: result.structure)
                }
                package.surveyPhotos = photoCapture.registered(house:package.house,scans:result.structure.rooms,alignSingleRoom:false)
                package.surveyPhotoAssets = photoCapture.assets
                let record = try store.saveHouse(package)
                Task { await persistence.complete() }
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

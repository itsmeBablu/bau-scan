#if canImport(RoomPlan)
import SwiftUI

/// Full-screen scan view: guidance, Cancel / Done, processing,
/// saving to `RoomStore` and returning to library.
/// House mode persists completed rooms in shared coordinates before final packaging.
struct ScanView: View {
    @Environment(RoomStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var cameraResource:LazyCaptureResource<ScanCoordinator>
    private var coordinator:ScanCoordinator { cameraResource.value }
    @State private var saveError: AppError?
    @State private var failedSave: ScanCoordinator.State?
    @State private var radiatorScanner: HouseRadiatorScanCoordinator?
    @State private var radiators: [HouseRadiator] = []
    @State private var radiatorBusy = false
    @State private var pins = CapturePins()
    @State private var photoCapture = HouseSurveyPhotoCapture()
    @State private var cameraLive = false
    @AppStorage(ScanPhotoPolicy.preferenceKey) private var appCameraPhotos = true
    @Environment(\.projectPreferences) private var projectPreferences
    @Environment(\.locale) private var locale
    private var cameraPhotos:Bool { ProjectPreferenceResolution.photos(projectPreferences,appDefault:appCameraPhotos) }
    @Environment(\.scenePhase) private var scenePhase
    private let workspace: RenovationWorkspace?
    @State private var persistence: CapturePersistence
    private var captureID: UUID { persistence.id }
    let voiceProjectID: UUID?
    let mode: ScanMode
    /// Created item (room or house) passed to caller to display.
    var onSaved: (LibraryItem) -> Void

    init(mode: ScanMode = .room, voiceProjectID: UUID? = nil, workspace: RenovationWorkspace? = nil, preparedPersistence: CapturePersistence? = nil, onSaved: @escaping (LibraryItem) -> Void = { _ in }) {
        self.workspace = workspace
        self.voiceProjectID = voiceProjectID
        self.mode = mode
        self.onSaved = onSaved
        let disk = preparedPersistence ?? CapturePersistence(kind:mode == .house ? .house : .room,projectID:voiceProjectID)
        _persistence = State(initialValue:disk)
        let voiceEnabled = voiceProjectID.flatMap { workspace?.project($0)?.details?.preferences?.voice } != false
        _cameraResource = State(initialValue:LazyCaptureResource {
            let scanner = ScanCoordinator(mode:mode); scanner.persistence = disk
            scanner.prepareVoiceRecording = voiceEnabled
            return scanner
        })
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

                CapturePinOverlay(session:coordinator.arSession,pins:pins,scan:{ coordinator.tapGeometry }).ignoresSafeArea()
                overlay
            }
        }
        .modifier(CaptureAwakeModifier())
        .onAppear { photoCapture.persistence = persistence }
        .onDisappear { radiatorScanner?.stop(); coordinator.stop() }
        .modifier(ScanPhotoFeedback(count:photoCapture.completed))
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
                        RoundedRectangle(cornerRadius: DS.Radius.compact).stroke(.green,lineWidth: 2)
                            .frame(width: rect.width,height: rect.height).position(x: rect.midX,y: rect.midY)
                    }
                }
                if let rect = scanner.bodyRect(in: geometry.size) {
                    ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.compact).stroke(.cyan,lineWidth: 3)
                        .frame(width: rect.width,height: rect.height).position(x: rect.midX,y: rect.midY)
                    }
                }
            }.ignoresSafeArea().allowsHitTesting(false)
        }
        VStack {
            HStack {
                Button(role: .cancel) { coordinator.cancel(); dismiss() } label: { Text("Close") }
                    .buttonStyle(.bordered)
                Spacer()
                Text(persistence.organization?.displayName(locale:locale) ?? AppLanguage.text(mode == .house ? "House" : "Room",locale:locale))
                    .font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                Button { Task { await finishScan() } } label: { Text(mode == .house ? "scan.finishHouse" : "scan.finish") }
                    .dsProminentControl()
                    .disabled((coordinator.state != .scanning && coordinator.state != .roomSaved) || radiatorBusy || photoCapture.busy)
            }
            .padding()
            Spacer()
            if let failedSave { Button("Retry finishing") { Task { await saveState(failedSave) } }.dsProminentControl() }
            if case .failed = coordinator.state {
                Button("Retry finishing") { coordinator.retryFinish() }.dsProminentControl()
            }
            if let diagnostic = coordinator.cameraDiagnostic {
                Text(diagnostic).font(.callout).padding().dsMaterial(in:RoundedRectangle(cornerRadius:DS.Radius.panel))
            }
            if persistence.failure != nil { Label("Saving failed · draft retained",systemImage:"exclamationmark.triangle").font(.caption).padding(8).dsMaterial(in:Capsule()) }
            HStack {
                if workspace?.project(voiceProjectID ?? UUID())?.details?.preferences?.voice != false { VoiceNoteHUD(reference:captureReference,persistence:persistence,workspace:workspace,projectID:voiceProjectID,
                    pins:pins,position:{ coordinator.noteSurface() },pose:{ coordinator.notePose() },roomID:{ mode == .house ? coordinator.liveRoomID : captureID },level:{ coordinator.liveLevel },borrowCaptureAudioSession:true,nearbyPin:{ pins.nearest(to:$0) },selectedPin:pins.selection,onPin:{ pins.put($0) },onTextSaved:{ pins.selected = nil })
                    .disabled(coordinator.state != .scanning) }
                Spacer()
                if ScanPhotoPolicy.buttonVisible(enabled:cameraPhotos,cameraRunning:cameraLive) {
                    ScanPhotoButton(busy:photoCapture.busy) { Task { await photoCapture.capture(session:coordinator.arSession,roomID:mode == .house ? coordinator.liveRoomID : captureID,level:coordinator.liveLevel) } }
                }
            }.padding(.horizontal,20).padding(.bottom,20)

        }
        switch coordinator.state {
        case .processing, .merging:
            VStack(spacing: 12) {
                ProgressView()
                Text(coordinator.state == .merging ? "scan.merging" : "scan.processing")
            }
            .padding(24)
            .dsMaterial(in:RoundedRectangle(cornerRadius: DS.Radius.floating))
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
        Task { await saveState(state) }
    }
    private func saveState(_ state: ScanCoordinator.State) async {
        switch state {
        case .scanning:
            if let radiatorScanner { radiatorScanner.resume() } else { startAutomaticRadiators() }
        case .roomSaved:
            radiatorScanner?.pause()
        case .finished(let result):
            do {
                let name = store.proposedName(for: result.scan.sectionLabels.first ?? .unidentified)
                var scan = result.scan; scan.id = captureID
                let plan = FloorPlanBuilder().build(from:scan,name:name)
                var package = RoomPackage(record: RoomRecord(plan: plan), plan: plan, scan: scan,
                                          capturedRoomData: result.capturedRoomData, usdzData: result.usdzData, usdzMeshData: result.usdzMeshData,
                                          thumbnailPNG: PlanRenderer.thumbnailPNG(for: plan))
                package.surveyPhotos = photoCapture.registered(house:House(room:plan),scans:[scan],alignSingleRoom:true)
                package.surveyPhotoAssets = try await photoCapture.assets()
                let output = store.packageURL(for:package.record),finished = package
                try await Task.detached(priority:.userInitiated) { try finished.write(to:output) }.value
                let record = package.record; store.reload()
                try await persistence.registerOrganization(for:.init(kind:.room,itemID:record.id,library:store.isCloud ? "icloud" : "local"),catalogueRoot:workspace?.notesRoot ?? StorageLocation.local().documentsURL)
                failedSave = nil; await persistence.complete()
                onSaved(.room(record))
                dismiss()
            } catch {
                failedSave = state
                await persistence.state(.failed)
                saveError = .storageFailed(error.localizedDescription)
            }
        case .finishedHouse(let result):
            do {
                let extras = result.rooms.mapValues { HousePackage.RoomExtras(capturedRoomData: $0.capturedRoomData, usdzData: $0.usdzData, usdzMeshData: $0.usdzMeshData) }
                let name = store.proposedHouseName()
                var package = try await Task.detached(priority:.userInitiated) {
                    try HousePackage.assemble(structure:result.structure,name:name,capturedStructureData:result.capturedStructureData,usdzData:result.usdzData,roomExtras:extras)
                }.value
                package.house.id = captureID
                package.record.id = captureID
                package.structure?.id = captureID
                if !radiators.isEmpty {
                    package.radiators = try HouseRadiatorRegistration.associate(radiators,house: package.house,structure: result.structure)
                }
                package.surveyPhotos = photoCapture.registered(house:package.house,scans:result.structure.rooms,alignSingleRoom:false)
                package.surveyPhotoAssets = try await photoCapture.assets()
                let output = store.packageURL(for:package.record),finished = package
                try await Task.detached(priority:.userInitiated) { try finished.write(to:output) }.value
                let record = package.record; store.reload()
                try await persistence.registerOrganization(for:.init(kind:.house,itemID:record.id,library:store.isCloud ? "icloud" : "local"),catalogueRoot:workspace?.notesRoot ?? StorageLocation.local().documentsURL)
                failedSave = nil; await persistence.complete()
                onSaved(.house(record))
                dismiss()
            } catch {
                failedSave = state
                await persistence.state(.failed)
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

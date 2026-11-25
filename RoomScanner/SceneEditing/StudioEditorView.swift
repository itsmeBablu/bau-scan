import SwiftUI
import UniformTypeIdentifiers

private struct StudioFile: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    init(_ data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct StudioProjectView: View {
    let seed: SceneEditDocument
    let storageRoot: URL
    @State private var loaded: SceneEditDocument?
    @State private var photos: [SurveyPhotoImage] = []
    @State private var error: String?
    var body: some View {
        Group {
            if let loaded { StudioEditorView(document: loaded,storageURL: SceneEditStore.url(root: storageRoot,source: seed.source,id: seed.sourceID),photos:photos) }
            else if let error { ContentUnavailableView("Could not open design",systemImage: "exclamationmark.triangle",description: Text(error)) }
            else { ProgressView("Opening Studio…") }
        }
        .task(id:storageRoot.path+seed.source.rawValue+seed.sourceID.uuidString) {
            loaded = nil; error = nil; photos = []
            let source = seed.source, id = seed.sourceID, house = seed.shell, root = storageRoot
            photos = (try? await Task.detached { () throws -> [SurveyPhotoImage] in
                if source == .technical {
                    let url = root.appendingPathComponent("TechnicalRooms").appendingPathComponent(id.uuidString).appendingPathExtension("technicalroom")
                    return SurveyPhotoStore.images(technical:try TechnicalRoomPackage.read(from:url),studio:true)
                }
                let location = StorageLocation(kind:.local,documentsURL:root)
                let url = source == .house ? location.housesURL.appendingPathComponent(id.uuidString).appendingPathExtension(FileLayout.housePackageExtension) :
                    location.roomsURL.appendingPathComponent(id.uuidString).appendingPathExtension(FileLayout.packageExtension)
                return try SurveyPhotoStore.images(from:url,house:house)
            }.value) ?? []
            guard !Task.isCancelled else { return }
            do {
                let url = SceneEditStore.url(root: storageRoot,source: seed.source,id: seed.sourceID)
                let document = try await Task.detached { () throws -> SceneEditDocument in
                    var value = try SceneEditStore.read(url,source: seed.source,id: seed.sourceID) ?? seed
                    if value.floorRegions == nil {
                        let location = StorageLocation(kind: .local,documentsURL: storageRoot)
                        if value.source == .house {
                            let package = location.housesURL.appendingPathComponent(value.sourceID.uuidString).appendingPathExtension(FileLayout.housePackageExtension)
                            value.recoverFloorRegions(scans: (try? HousePackage.readStructure(from: package))?.rooms ?? [])
                        } else if value.source == .room {
                            let package = location.roomsURL.appendingPathComponent(value.sourceID.uuidString).appendingPathExtension(FileLayout.packageExtension)
                            value.recoverFloorRegions(scans: (try? RoomPackage.readScan(from: package)).map { [$0] } ?? [])
                        }
                    }
                    return value
                }.value
                try document.validate(); guard !Task.isCancelled else { return }; loaded = document
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

struct StudioEditorView: View {
    var photos: [SurveyPhotoImage] = []
    @State private var showPhotos = true
    @State private var selectedPhoto: SurveyPhotoImage?
    @State private var multipleSelection = false
    let storageURL: URL
    @State private var session: SceneEditSession
    @State private var controller = StudioSceneController()
    @State private var moving = false
    @State private var rotating = false
    @State private var snapping = true
    @State private var allowOverlap = false
    @State private var cutaway = false
    @State private var showPlan = false
    @State private var showDimensions = false
    @State private var reset = 0
    @State private var story: Int
    @State private var showInspector = false
    @State private var showAppearance = false
    @State private var showEngineering = false
    @State private var showModelLibrary = false
    @State private var landscape = false
    @State private var canvasWidth: CGFloat = 393
    @State private var modelSearch = ""
    @State private var modelCategory = "All"
    @State private var error: String?
    @State private var status = ""
    @State private var busy = false
    @State private var hasSaved = false
    @State private var exportFile: StudioFile?
    @State private var exportType = UTType.data
    @State private var exportName = "Design"
    @State private var exporting = false
    @State private var exportTask: Task<Void,Never>?
    @State private var exportProgress = 0.0
    @State private var importing = false
    @State private var equipmentEditor: SceneEditObject?
    @State private var confirmClose = false
    @FocusState private var viewportFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    init(document: SceneEditDocument,storageURL: URL,photos: [SurveyPhotoImage] = []) {
        self.photos = photos
        self.storageURL = storageURL
        _session = State(initialValue: SceneEditSession(document))
        _story = State(initialValue: document.shell.stories.first?.index ?? 0)
    }
    var body: some View {
        editorLayout
        .disabled(busy).allowsHitTesting(!busy)
        .overlay {
            if exportTask != nil {
                VStack(spacing:12) {
                    ProgressView("export.generating",value:exportProgress,total:1)
                    Button("Cancel") { exportTask?.cancel() }
                }.padding(24).frame(width:280).background(.regularMaterial,in:RoundedRectangle(cornerRadius:16))
            }
        }
        .navigationTitle(session.document.title)
        #if os(macOS)
        .background(StudioWindowGuard(dirty:{ session.dirty },save:{ try await persistDesign() }))
        #endif
        .focusedSceneValue(\.studioSession, session)
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement:.cancellationAction) { closeButton }
            ToolbarItem(placement:.primaryAction) { Menu("Design actions",systemImage:"ellipsis.circle") { designActions } }
            ToolbarItem(placement:.confirmationAction) { saveButton }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in landscape = size.width > size.height; canvasWidth = size.width }
        .sheet(isPresented: Binding(get: { showInspector && !landscape },set: { if !landscape { showInspector = $0 } })) {
            NavigationStack {
                inspector.navigationTitle("Object properties")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showInspector = false } } }
            }
            .sheet(item: $equipmentEditor) { item in equipmentSheet(item) }
            .sheet(isPresented: $showEngineering) { StudioEngineeringView(session: session) }
            .presentationDetents([.medium,.large])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        #else
        .frame(minWidth: 760,minHeight: 650)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if session.document.shell.stories.count > 1 {
                    Picker("house.story", selection: $story) {
                        ForEach(session.document.shell.stories, id: \.index) { story in
                            Text(StoryNaming.localizedName(for: story.index)).tag(story.index)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            ToolbarItem(placement: .principal) {
                Picker("View mode", selection: Binding(
                    get: { session.document.engineering?.view ?? .all },
                    set: { v in try? session.change { $0.engineering = ($0.engineering ?? .init()); $0.engineering?.view = v } }
                )) {
                    Text("All").tag(StudioEngineering.ViewMode.all)
                    Text("Existing").tag(StudioEngineering.ViewMode.existing)
                    Text("Demolition").tag(StudioEngineering.ViewMode.demolition)
                    Text("Proposed").tag(StudioEngineering.ViewMode.proposed)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
            }
            ToolbarItemGroup(placement: .automatic) {
                Toggle(isOn: $showPhotos) { Label("Photos", systemImage: "camera") }
                Toggle(isOn: $showDimensions) { Label("Dimensions", systemImage: "ruler") }
                Button { showAppearance = true } label: { Label("Appearance", systemImage: "paintpalette") }
                Button { showEngineering = true } label: { Label("Engineering", systemImage: "hammer") }
                Button { export3D(.usdz) } label: { Label("Export", systemImage: "square.and.arrow.up") }
                Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
                saveButton
            }
        }
        .inspector(isPresented: $showInspector) {
            inspector
                .frame(minWidth: 280, idealWidth: 320)
        }
        #endif
        .tint(.blue)
        .toolbar { selectionToolbar }
        .sheet(item:$selectedPhoto) { photo in
            SurveyPhotoGallery(photos:photos,initial:photo.id) { controller.flyToPhoto($0.photo) }
        }
        .onChange(of:showPhotos) { _,value in controller.setPhotos(value ? photos : []) }
        .onChange(of:photos) { _,value in controller.setPhotos(showPhotos ? value : []) }
        .onAppear { configureInteraction() }
        .onDisappear { exportTask?.cancel(); controller.onSelect = nil; controller.onMove = nil; controller.onRotate = nil; controller.onPhoto = nil }
        .sheet(isPresented: Binding(get: { showEngineering && !inspectorPresentedModally },set: { showEngineering = $0 })) { StudioEngineeringView(session: session) }
        .onChange(of: story) { _,_ in session.select(nil,multiple:false) }
        .onChange(of: session.selectedIDs) { _,ids in
            controller.selectedIDs = ids
        }
        .onChange(of:session.selectedID) { _,id in
            if !multipleSelection { session.selectedIDs = Set(id.map { [$0] } ?? []) }
        }
        .onChange(of: multipleSelection) { _,enabled in
            moving = false; rotating = false
            controller.onSelect = { session.select($0,multiple:enabled) }
            if !enabled { session.select(session.selectedID,multiple:false) }
        }
        .onChange(of: session.document.objects.map(\.id)) { _,ids in
            session.selectedIDs.formIntersection(Set(ids))
            if let selected = session.selectedID,!ids.contains(selected) { session.selectedID = nil }
        }
        .interactiveDismissDisabled(session.dirty || busy)
        .confirmationDialog("Save this design before closing?",isPresented: $confirmClose,titleVisibility: .visible) {
            Button("Save and close") { save(close: true) }
            Button("Discard unsaved edits",role: .destructive) { dismiss() }
        }
        .sheet(isPresented: $showAppearance) { appearance }
        .sheet(isPresented: $showModelLibrary) { modelLibrary }
        #if os(macOS)
        .sheet(item: $equipmentEditor) { item in equipmentSheet(item) }
        #endif
        .alert("Studio",isPresented: Binding(get: { error != nil },set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        .fileExporter(isPresented: $exporting,document: exportFile,contentType: exportType,defaultFilename: exportName) { result in
            if case .failure(let failure) = result { error = failure.localizedDescription }
        }
        .fileImporter(isPresented: $importing,allowedContentTypes: [.json]) { result in importProject(result) }
    }

    @ToolbarContentBuilder private var selectionToolbar: some ToolbarContent {
        ToolbarItem {
            Menu {
                Toggle("Select multiple",isOn: $multipleSelection)
                Button("Select all objects on this floor") { selectAllObjects() }
                Button("Delete selected",role: .destructive) { perform { try session.deleteSelection() } }
                    .disabled(session.selectedIDs.isEmpty)
                Button("Clear selection") { session.select(nil,multiple: false) }
            } label: { Label("Selection",systemImage: "checkmark.circle") }
        }
        ToolbarItem {
            if !photos.isEmpty { Toggle("Photos",isOn: $showPhotos).toggleStyle(.button) }
        }
    }
    private func selectAllObjects() {
        multipleSelection = true; session.selectedID = nil
        session.selectedIDs = Set(session.document.presentationObjects.filter { $0.story == story }.map(\.id))
    }
    private func configureInteraction() {
            hasSaved = FileManager.default.fileExists(atPath: storageURL.path)
            session.onSave = { save() }
            session.selectAllOnFloor = {
                multipleSelection = true
                session.selectedIDs = Set(session.document.presentationObjects.filter { $0.story == story }.map(\.id))
                session.selectedID = nil
            }
            controller.setPhotos(showPhotos ? photos : [])
            controller.onPhoto = { id in selectedPhoto = photos.first { $0.id == id } }
            controller.onSelect = { session.select($0,multiple:multipleSelection) }
            controller.onRotate = { id,angle in
                guard var item = session.document.objects.first(where: { $0.id == id }) else { return false }
                item.yaw += angle
                if snapping { item.yaw = (item.yaw/(Double.pi/12)).rounded()*(Double.pi/12) }
                do { try update(item); return true } catch { self.error = error.localizedDescription; return false }
            }
            controller.onMove = { id,position in
                guard var item = session.document.objects.first(where: { $0.id == id }) else { return false }
                item.position = position
                if snapping { item = StudioPlacement.snapped(item,in: session.document,axis: controller.movementAxis) }
                do { try update(item); return true } catch { self.error = error.localizedDescription; return false }
            }
    }

    @ViewBuilder private var editorLayout: some View {
        #if os(iOS)
        VStack(spacing:0) {
            Picker("Interaction",selection:interaction) { Text("Orbit").tag("orbit"); Text("Move").tag("move"); Text("Rotate").tag("rotate") }
                .pickerStyle(.segmented).padding(.horizontal)
            if session.document.shell.stories.count > 1 {
                Picker("Level",selection:$story) { ForEach(session.document.shell.stories,id: \.index) { Text(StoryNaming.localizedName(for:$0.index)).tag($0.index) } }
            }
            HStack(spacing:0) {
                ZStack {
                    viewport
                    if session.document.source == .technical && session.document.objects.isEmpty { technikEmptyState }
                }
                if showInspector && landscape { inspector.frame(width:min(340,canvasWidth*0.4)) }
            }
            selectionHUD
            HStack {
                Button("Objects",systemImage:"slider.horizontal.3") { showInspector.toggle() }
                Button(showPlan ? "3D" : "Floor plan",systemImage:"square") { showPlan.toggle() }
                Button("Reset camera",systemImage:"scope") { reset += 1 }
            }.buttonStyle(.bordered).padding(8)
            if busy { ProgressView("Working…") }
            else if !status.isEmpty { Text(status).font(.caption).padding(.horizontal) }
        }
        #else
        VStack(spacing: 0) {
            HStack {
                Picker("Interaction",selection: interaction) { Text("Orbit").tag("orbit"); Text("Move").tag("move"); Text("Rotate").tag("rotate") }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 260)
                Spacer()
                Button { showPlan.toggle() } label: { Label(showPlan ? "3D" : "2D",systemImage: showPlan ? "cube" : "square") }
                Button { reset += 1 } label: { Label("Reset camera",systemImage: "scope") }.labelStyle(.iconOnly)
                Button { showInspector.toggle() } label: { Label("Objects",systemImage: "slider.horizontal.3") }.labelStyle(.iconOnly)
            }.padding(10)
            if session.document.shell.stories.count > 1 {
                Picker("Floor",selection: $story) {
                    ForEach(session.document.shell.stories,id: \.index) { Text(StoryNaming.localizedName(for: $0.index)).tag($0.index) }
                }.padding(.horizontal)
            }
            ZStack {
                viewport
                if session.document.source == .technical && session.document.objects.isEmpty {
                    technikEmptyState
                }
            }
            if showInspector {
                inspector.frame(maxHeight: 270)
            }
            HStack {
                Text(busy ? "Working…" : status.isEmpty ? rotating ? "Drag the rotation ring. Changes are design edits." : moving ? "Drag an object to move it. Changes are design edits." : "Tap furniture to select · drag to orbit · pinch to zoom" : status)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Text(session.dirty || !hasSaved ? "Unsaved design" : "Design saved").font(.caption).foregroundStyle(.secondary)
            }.padding(10)
        }
        #endif
    }
    private var technikEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 38))
                .foregroundStyle(Color.accentColor)
            Text("Technik Studio · No Equipment Placed")
                .font(.headline)
            Text("Generate a complete standard technical room layout with boiler, buffer tank, pump, manifold, expansion vessel, electrical panel, and pipes.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 300)
            HStack(spacing: 12) {
                Button {
                    perform { try session.change { $0.generateModularTechnikLayout() } }
                } label: {
                    Label("Generate equipment", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                Button {
                    showModelLibrary = true
                } label: {
                    Label("Browse MEP", systemImage: "plus")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.horizontal, 24)
    }
    private var phoneHeader: some View {
        VStack(alignment: .leading,spacing: 8) {
            if textSize.isAccessibilitySize {
                Text(session.document.source == .technical ? "Design" : "Design")
                    .font(.headline).padding(.horizontal,12).padding(.vertical,8)
                    .background(.regularMaterial,in: Capsule())
            }
            HStack(spacing: 12) {
                Button { requestClose() } label: { Image(systemName: "xmark").frame(width: 44,height: 44) }
                    .accessibilityLabel("Close Studio").background(.regularMaterial,in: Circle())
                if !textSize.isAccessibilitySize {
                    VStack(alignment: .leading,spacing: 2) {
                        Text(session.document.source == .technical ? "Design" : "Design").font(.headline)
                        Text(session.dirty || !hasSaved ? "Unsaved design" : "Design saved").font(.caption).foregroundStyle(.secondary)
                    }.lineLimit(1).padding(.horizontal,14).padding(.vertical,8).background(.regularMaterial,in: Capsule())
                }
                Spacer(minLength: 0)
                saveButton.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).foregroundStyle(.white)
            }
        }
    }
    @ViewBuilder private var phoneDock: some View {
        if textSize.isAccessibilitySize {
            ScrollView(.horizontal) {
                HStack(spacing: 8) { phoneDockActions }.frame(minWidth: 660).padding(.horizontal,8).padding(.vertical,6)
            }.scrollIndicators(.hidden).fixedSize(horizontal: false,vertical: true)
                .background(.regularMaterial,in: RoundedRectangle(cornerRadius: 22))
        } else {
            HStack(spacing: 0) { phoneDockActions }.padding(.horizontal,4).padding(.vertical,3).background(.regularMaterial,in: Capsule())
        }
    }
    @ViewBuilder private var selectionHUD: some View {
        ScrollView(.horizontal) {
        HStack {
            Toggle("Select multiple",isOn:$multipleSelection).toggleStyle(.button)
            if multipleSelection {
                Text(AppLanguage.text("Selected")+": "+String(session.selectedIDs.count))
                Button("Delete selected",role:.destructive) { perform { try session.deleteSelection() } }
                    .disabled(session.selectedIDs.isEmpty)
                Button("Clear") { session.selectedIDs = []; session.selectedID = nil }
            }
        }.padding(8)
        }.scrollIndicators(.hidden).fixedSize(horizontal:false,vertical:true)
            .background(.regularMaterial,in:RoundedRectangle(cornerRadius:12))
        if let item = session.selected {
            HStack {
                VStack(alignment: .leading,spacing: 3) {
                    Text(item.name).font(.subheadline.bold())
                    if rotating { Text(snapping ? "Drag the ring to rotate · snapping uses 15° steps" : "Drag the ring to rotate").font(.caption).foregroundStyle(.secondary) }
                    else if moving { Text("Drag X / Y / Z arrows or drag the object across the floor").font(.caption).foregroundStyle(.secondary) }
                    Text("\(item.size.x,specifier: "%.2f") × \(item.size.y,specifier: "%.2f") × \(item.size.z,specifier: "%.2f") m").font(.caption).monospacedDigit()
                }
                Spacer()
                Button("Edit") { showInspector = true }.buttonStyle(.bordered)
            }.padding(.horizontal,12).padding(.vertical,6).background(.regularMaterial,in: RoundedRectangle(cornerRadius: 14))
        }
    }
    @ViewBuilder private var phoneDockActions: some View {
        Button { showModelLibrary = true } label: { dockLabel(session.document.source == .technical ? "Equipment" : "Models",icon: session.document.source == .technical ? "pipe.and.drop" : "sofa.fill",active: showModelLibrary) }
        Menu {
            Picker("Interaction",selection: interaction) {
                Text("Orbit").tag("orbit"); Text("Move").tag("move"); Text("Rotate").tag("rotate")
            }
        } label: { dockLabel(rotating ? "Rotate" : moving ? "Move" : "Orbit",icon: rotating ? "arrow.triangle.2.circlepath" : moving ? "arrow.up.and.down.and.arrow.left.and.right" : "rotate.3d",active: !showPlan) }
            .accessibilityLabel("Interaction mode").accessibilityValue(rotating ? "Rotate" : moving ? "Move" : "Orbit").disabled(showPlan)
        Button { showInspector.toggle() } label: { dockLabel("Edit",icon: "slider.horizontal.3",active: showInspector) }
        Button { showAppearance = true } label: { dockLabel("Style",icon: "paintpalette",active: showAppearance) }
        Button { showDimensions.toggle() } label: { dockLabel("Sizes",icon: "ruler",active: showDimensions) }.accessibilityLabel("3D dimensions").accessibilityValue(showDimensions ? "On" : "Off")
        Menu { designActions } label: { dockLabel("More",icon: "ellipsis",active: showPlan || showEngineering) }
    }
    private var interaction: Binding<String> {
        Binding(get: { rotating ? "rotate" : moving ? "move" : "orbit" },set: { value in moving = value == "move"; rotating = value == "rotate" })
    }
    @ViewBuilder private var viewport: some View {
        if showPlan { Plan2DView(house: House(id: session.document.shell.id,name: session.document.title,stories: session.document.plan.stories.filter { $0.index == story })) }
        else {
            StudioViewport(controller: controller,document: session.document,story: story,cutaway: cutaway,selected: session.selectedID,moving: moving && (session.document.engineering?.view == nil || session.document.engineering?.view == .all || session.document.engineering?.view == .proposed),reset: reset,showDimensions: showDimensions,rotating: rotating && (session.document.engineering?.view == nil || session.document.engineering?.view == .all || session.document.engineering?.view == .proposed))
                #if os(macOS)
                .focusable().focused($viewportFocused)
                .focusedValue(\.studioViewportSession,viewportFocused ? session : nil)
                .simultaneousGesture(TapGesture().onEnded { viewportFocused = true })
                .onKeyPress(keys:[.leftArrow,.rightArrow,.upArrow,.downArrow],phases:[.down,.repeat]) { press in
                    guard viewportFocused,press.modifiers.subtracting(.shift).isEmpty else { return .ignored }
                    let step = press.modifiers.contains(.shift) ? 0.10 : 0.01
                    nudgeSelected(dx:press.key == .leftArrow ? -step : press.key == .rightArrow ? step : 0,
                                  dz:press.key == .upArrow ? -step : press.key == .downArrow ? step : 0)
                    return .handled
                }
                .onDeleteCommand { if viewportFocused { perform { try session.deleteSelection() } } }
                #endif
                .frame(maxWidth: .infinity,minHeight: 200,maxHeight: .infinity)
        }
    }
    private var closeButton: some View { Button("Close") { requestClose() }.disabled(busy) }
    private func equipmentSheet(_ item: SceneEditObject) -> some View {
        StudioTechnicalDataView(data: item.technicalData ?? .init()) { data in
            var updated = item; updated.technicalData = data; try session.update(updated)
        }
    }
    private func requestClose() { if session.dirty { confirmClose = true } else { dismiss() } }
    private var saveButton: some View { Button("Save") { save() }.disabled(busy || (!session.dirty && hasSaved)) }
    private var undoButton: some View { Button { session.undo() } label: { Label("Undo",systemImage: "arrow.uturn.backward") }.disabled(session.undoStack.isEmpty || busy) }
    private var catalogue: [SceneFurniture] {
        if session.document.source == .technical { return [.pipe,.roundDuct,.rectangularDuct,.boiler,.tank,.radiator,.pump,.manifold,.electricalPanel,.box,.cylinder] }
        return [.sofa,.bed,.chair,.table,.television,.cabinet,.refrigerator,.stove,.sink,.toilet,.bathtub,.shower,.washer,.desk,.officeChair,.conferenceTable,.computer,.monitor,.bookshelf,.whiteboard,.radiator,.box,.cylinder]
    }
    private var filteredCatalogue: [SceneFurniture] {
        catalogue.filter { family in
            let matchesSearch = modelSearch.isEmpty || family.title.localizedCaseInsensitiveContains(modelSearch)
            guard matchesSearch else { return false }
            if session.document.source == .technical || modelCategory == "All" { return true }
            switch modelCategory {
            case "Office":
                return [.desk, .officeChair, .conferenceTable, .computer, .monitor, .bookshelf, .whiteboard].contains(family)
            case "Living":
                return [.sofa, .bed, .chair, .table, .television, .cabinet, .bookshelf, .box, .cylinder].contains(family)
            case "Kitchen & Bath":
                return [.refrigerator, .stove, .sink, .toilet, .bathtub, .shower, .washer].contains(family)
            default:
                return true
            }
        }
    }
    private var modelMenu: some View { ForEach(catalogue) { family in Button(family.title) { add(family) } }.disabled(session.document.objects.count >= 500) }
    private var designOptions: some View {
        Menu { designActions } label: { Label("Design options",systemImage: "ellipsis.circle") }.disabled(busy)
    }
    @ViewBuilder private var designActions: some View {
                    undoButton
                    Button("Redo") { session.redo() }.disabled(session.redoStack.isEmpty)
                    Toggle("Multiple selection",isOn:$multipleSelection)
                    Button("Select all on this floor") {
                        multipleSelection = true; session.selectedID = nil
                        session.selectedIDs = Set(session.document.presentationObjects.filter { $0.story == story }.map(\.id))
                    }
                    Button("Delete selected",role:.destructive) { perform { try session.deleteSelection() } }
                        .disabled(session.selectedIDs.isEmpty)
                    Button("Clear selection") { session.select(nil,multiple:false) }
                    if !photos.isEmpty { Toggle("Photos",isOn:$showPhotos) }
                    Button(showPlan ? "Show 3D" : "Show 2D plan") { showPlan.toggle() }
                    Button("Reset camera") { reset += 1 }
                    Toggle("3D dimensions",isOn: $showDimensions)
                    if session.document.shell.stories.count > 1 {
                        Picker("Floor",selection: $story) { ForEach(session.document.shell.stories,id: \.index) { Text(StoryNaming.localizedName(for: $0.index)).tag($0.index) } }
                    }
                    Button("Engineering · renovation & issues") { showEngineering = true }
                    Button("Appearance") { showAppearance = true }
                    Toggle("Cutaway view · hide front walls",isOn: $cutaway)
                    Toggle("Snap · 5 cm grid and walls",isOn: $snapping)
                    Toggle("Allow overlaps · intentional connections",isOn: $allowOverlap)
                    Button("Check current floor overlaps") { checkOverlaps() }
                    if session.document.source == .technical {
                        Divider()
                        Button("Generate Technik equipment layout") {
                            perform { try session.change { $0.generateModularTechnikLayout() } }
                        }
                    }
                    Divider()
                    Menu(session.document.source == .technical ? "Add equipment" : "Add model") { modelMenu }
                    Button("Import design project…") { importing = true }
                    Menu("Export edited design") {
                        Button("PNG image · current view") { image() }.disabled(showPlan)
                        ForEach(StudioExporter.Format.allCases,id: \.self) { format in Button(format == .csv ? "Engineering register · CSV" : format == .project ? "Editable project · JSON" : format == .obj ? "OBJ + materials · current floor · ZIP" : format == .usdz ? "USDZ · current floor" : format.rawValue.uppercased()) { export(format) } }
                    }
    }
    private func dockLabel(_ title: String,icon: String,active: Bool = false) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 18,weight: .medium)).frame(height: 20)
            Text(title).font(.caption2.weight(.medium)).lineLimit(1)
        }.frame(maxWidth: .infinity,minHeight: 44)
            .foregroundStyle(active ? Color.accentColor : Color.primary)
            .background(active ? Color.accentColor.opacity(0.16) : Color.clear,in: RoundedRectangle(cornerRadius: 14))
            .accessibilityAddTraits(active ? .isSelected : [])
            .contentShape(Rectangle())
    }
    private var modelLibrary: some View {
        NavigationStack {
            ScrollView {
                if session.document.source == .technical {
                    Button {
                        perform {
                            try session.change { $0.generateModularTechnikLayout() }
                            showModelLibrary = false
                        }
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Generate standard equipment layout")
                                    .font(.subheadline.bold())
                                Text("Populate boiler, buffer tank, pump, manifold, panel, and pipes")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                if session.document.source != .technical {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(["All", "Office", "Living", "Kitchen & Bath"], id: \.self) { category in
                                Button {
                                    modelCategory = category
                                } label: {
                                    Text(category)
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(modelCategory == category ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                                        .foregroundStyle(modelCategory == category ? .black : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 4)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130),spacing: 12)],spacing: 12) {
                    ForEach(filteredCatalogue) { family in
                        Button { add(family) } label: {
                            VStack(spacing: 10) {
                                Image(systemName: family.symbol).font(.title2)
                                Text(family.title).font(.subheadline.weight(.semibold))
                                Text("\(family.defaultSize.x,specifier: "%.2f") × \(family.defaultSize.y,specifier: "%.2f") × \(family.defaultSize.z,specifier: "%.2f") m").font(.caption2).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity,minHeight: 100).padding(8)
                                .background(.quaternary,in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain).disabled(session.document.objects.count >= 500)
                    }
                }.padding()
            }
            .searchable(text: $modelSearch,prompt: "Find a model")
            .navigationTitle(session.document.source == .technical ? "MEP models" : "Furniture")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showModelLibrary = false } } }
        }
        #if os(iOS)
        .presentationDetents([.medium,.large]).presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 500,minHeight: 500)
        #endif
    }
    private var inspectorPresentedModally: Bool {
        #if os(iOS)
        showInspector && !landscape
        #else
        false
        #endif
    }
    private var inspector: some View {
        Form {
            Section {
                Picker("Selected object",selection: $session.selectedID) {
                    Text("Choose an object").tag(UUID?.none)
                    ForEach(session.document.objects.filter { $0.story == story }) { Text($0.name).tag(Optional($0.id)) }
                }
                if let item = session.selected {
                    StudioObjectFields(item: item,catalogue: catalogue,replace: { family in replace(item,with: family) }) { updated in perform { try update(updated) } }
                        .id(item.id)
                    Button("Engineering · phase, verification & issue") { showEngineering = true }
                    if session.document.engineering?.view == .existing || session.document.engineering?.view == .demolition {
                        Text("This view uses the saved scan envelope where available. Choose All or Proposed in Engineering to inspect design edits.").font(.caption).foregroundStyle(.secondary)
                    }
                    if session.document.source != .technical {
                        Button("Use furniture default size") { replace(item,with: item.family) }
                    }
                    if session.document.source == .technical {
                        Button("Equipment data · German references") { equipmentEditor = item }
                    }
                    if let reference = item.scanReference {
                        HStack {
                            Button("Fit scanned size") { var updated = item; updated.size = reference.size; perform { try update(updated) } }
                            Spacer()
                            Button("Restore scan position") {
                                var updated = item; updated.position = reference.position; updated.yaw = reference.yaw; updated.axis = reference.axis; updated.crossAxis = reference.crossAxis
                                perform { try update(updated) }
                            }
                        }
                    }
                    HStack {
                        Button("Duplicate") { duplicate(item) }.disabled(session.document.objects.count >= 500)
                        Spacer()
                        Button("Delete",role: .destructive) { perform { try session.change { $0.objects.removeAll { $0.id == item.id } }; session.selectedID = nil } }
                    }
                } else {
                    Text("The original scan is preserved. Add models from Design options, or select a recognised object. Unknown elements are not automatically invented.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.formStyle(.grouped)
    }
    private var appearance: some View {
        NavigationStack {
            Form {
                if session.document.source != .technical {
                    Section("Doors & windows · SmartBau style") {
                        Picker("Door template",selection: Binding(get: { session.document.doorTemplate ?? .single },set: { value in perform { try session.change { $0.doorTemplate = value } } })) {
                            ForEach(SceneEditDocument.DoorTemplate.allCases,id: \.self) { Text(AppLanguage.text($0.rawValue)).tag($0) }
                        }
                        Stepper("Door opening: \(Int(session.document.doorOpeningDegrees ?? 0))°",value: Binding(get: { session.document.doorOpeningDegrees ?? 0 },set: { value in perform { try session.change { $0.doorOpeningDegrees = value } } }),in: 0...120,step: 5)
                        Picker("Window template",selection: Binding(get: { session.document.windowTemplate ?? .casement },set: { value in perform { try session.change { $0.windowTemplate = value } } })) {
                            ForEach(SceneEditDocument.WindowTemplate.allCases,id: \.self) { Text($0 == .doubleHung ? "Double hung" : $0.rawValue.capitalized).tag($0) }
                        }
                        if session.document.windowTemplate == nil || session.document.windowTemplate == .casement {
                            Stepper("Window opening: \(Int(session.document.windowOpeningDegrees ?? 0))°",value: Binding(get: { session.document.windowOpeningDegrees ?? 0 },set: { value in perform { try session.change { $0.windowOpeningDegrees = value } } }),in: 0...90,step: 5)
                        }
                        Text("Templates fit the scanned opening. Leaf, frame, hardware and operation are design choices, not detected construction details. Opening poses do not verify clearances.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if session.document.source == .technical {
                    Section("Technik templates") {
                        Picker("Template",selection: Binding(get: { session.document.technicalTemplate ?? .captured },set: { value in
                            perform { try session.change { $0.applyTechnicalTemplate(value) } }
                        })) {
                            ForEach(SceneEditDocument.TechnicalTemplate.allCases,id: \.self) { Text($0.title).tag($0) }
                        }
                        Text("Generic equipment shapes stay within the measured envelope. Category colours are a display palette, not system identification. Captured colours restores retained camera samples. Templates never alter dimensions, routes or source evidence.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Interior") {
                  if session.document.source != .technical {
                    Picker("Style",selection: Binding(get: { session.document.interior },set: { value in perform { try session.change { $0.apply(value) } } })) {
                        ForEach(SceneEditDocument.Interior.allCases,id: \.self) { Text(AppLanguage.text($0.rawValue)).tag($0) }
                    }
                  }
                    ColorPicker("Walls",selection: colorBinding(wall: true),supportsOpacity: false)
                    ColorPicker("Floor",selection: colorBinding(wall: false),supportsOpacity: false)
                    if session.document.source != .technical {
                        Picker("Floor finish",selection: Binding(get: { session.document.floorFinish ?? .wood },set: { value in perform { try session.change { $0.floorFinish = value; $0.floorPatternSize = nil } } })) {
                            ForEach(SceneEditDocument.FloorFinish.allCases,id: \.self) { Text(AppLanguage.text($0.rawValue)).tag($0) }
                        }
                        if session.document.floorFinish != .plain {
                            Stepper("Pattern repeat: \((session.document.floorPatternSize ?? (session.document.floorFinish == .tile ? 0.3 : 0.72)).formatted()) m",value: Binding(get: { session.document.floorPatternSize ?? (session.document.floorFinish == .tile ? 0.3 : 0.72) },set: { value in perform { try session.change { $0.floorPatternSize = value } } }),in: 0.1...2,step: 0.05)
                            Text("Presentation pattern only; not a measured tile or board size.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if session.document.source != .technical { Section("Lighting and mood") {
                    Picker("Lighting",selection: Binding(get: { session.document.lighting },set: { value in perform { try session.change { $0.lighting = value } } })) {
                        ForEach(SceneEditDocument.Lighting.allCases,id: \.self) { Text(AppLanguage.text($0.rawValue)).tag($0) }
                    }
                    Picker("Season",selection: Binding(get: { session.document.season },set: { value in perform { try session.change { $0.season = value } } })) {
                        ForEach(SceneEditDocument.Season.allCases,id: \.self) { Text(AppLanguage.text($0.rawValue)).tag($0) }
                    }
                    Text("Season changes the lighting mood. Styles recolour design furniture; scan evidence and measured geometry stay intact. Exports preserve model materials; PNG captures this lighting and camera view.").font(.caption)
                } }
            }.formStyle(.grouped).navigationTitle("Appearance")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAppearance = false } } }
        }
        #if os(macOS)
        .frame(minWidth: 450,minHeight: 400)
        #else
        .presentationDetents([.medium,.large]).presentationDragIndicator(.visible)
        #endif
    }
    private func colorBinding(wall: Bool) -> Binding<Color> {
        Binding(get: { StudioObjectFields.color(wall ? session.document.wallColor : session.document.floorColor) },set: { color in
            guard let rgb = StudioObjectFields.rgb(color) else { return }
            perform { try session.change { if wall { $0.wallColor = rgb } else { $0.floorColor = rgb } } }
        })
    }
    private func perform(_ action: () throws -> Void) { do { try action(); status = "" } catch { self.error = error.localizedDescription } }
    private func update(_ item: SceneEditObject) throws {
        if !allowOverlap,let old = session.document.objects.first(where: { $0.id == item.id }),
           old.position != item.position || old.size != item.size || old.yaw != item.yaw || old.axis != item.axis || old.crossAxis != item.crossAxis {
            try StudioPlacement.check(item,in: session.document)
        }
        try session.update(item)
    }
    private func replace(_ item: SceneEditObject,with family: SceneFurniture) {
        perform {
            var next = item; next.replaceFamily(family,preserveMeasurements: session.document.source == .technical)
            next = try StudioPlacement.available(next,in: session.document,allowOverlap: allowOverlap)
            try session.update(next)
            status = session.document.source == .technical ? "Element type changed. Survey dimensions and orientation are preserved." : "Using default \(family.title.lowercased()) dimensions. Fit scanned size restores the scan envelope."
        }
    }
    private func add(_ family: SceneFurniture) {
        let bounds = session.document.shell.bounds,size = family.defaultSize
        let item = SceneEditObject(origin: "User-added design model; not scan evidence",name: family.title,family: family,position: .init(x: bounds.isEmpty ? 0 : bounds.center.x,y: size.y/2,z: bounds.isEmpty ? 0 : -bounds.center.y),size: size,story: story)
        perform {
            try session.addDesignObject(item,allowOverlap: allowOverlap)
            showModelLibrary = false
        }
    }
    private func duplicate(_ item: SceneEditObject) {
        var copy = item; copy.id = UUID(); copy.sourceID = nil; copy.scanReference = nil; copy.origin = "User-created duplicate"; copy.name = String((item.name+" copy").prefix(120)); copy.position.x += 0.25
        perform {
            try session.addDesignObject(copy,allowOverlap: allowOverlap)
        }
    }
    private func nudgeSelected(dx: Double, dz: Double) {
        perform { try session.nudgeSelection(dx:dx,dz:dz,allowOverlap:allowOverlap) }
    }

    private func export3D(_ format: StudioExporter.Format) {
        export(format)
    }

    private func save(close: Bool = false) {
        Task { @MainActor in
            do {
                try await persistDesign()
                if close { dismiss() }
            } catch { self.error = error.localizedDescription }
        }
    }
    private func persistDesign() async throws {
        guard !busy else { throw CocoaError(.fileWriteUnknown) }
        busy = true; defer { busy = false }
        let document = session.document
        let committed = try await Task.detached { try SceneEditStore.write(document,to:storageURL) }.value
        session.markSaved(committed); hasSaved = true; status = "Design saved separately from the scan."
    }
    private func image() {
        perform { exportFile = StudioFile(try controller.png()); exportType = .png; exportName = "Edited-design.png"; exporting = true }
    }
    private func checkOverlaps() {
        busy = true; let document = session.document,floor = story
        Task { @MainActor in
            defer { busy = false }
            let conflicts = await Task.detached { StudioPlacement.conflicts(in: document,story: floor) }.value
            if conflicts.isEmpty { status = "No object-envelope overlaps found on this floor." }
            else { error = "Envelope overlaps (up to 20 shown):\n"+conflicts.joined(separator: "\n")+"\nOriginal scan geometry is unchanged. Review intentional connections separately." }
        }
    }
    private func export(_ format: StudioExporter.Format) {
        guard !busy,exportTask == nil else { return }
        busy = true; exportProgress = 0
        let document = session.document,floor = story
        exportTask = Task { @MainActor in
            defer { busy = false; exportTask = nil }
            do {
                let data = try await StudioExporter.dataAsync(document,format:format,story:floor,progress:{ exportProgress = $0 })
                try Task.checkCancellation(); exportFile = StudioFile(data)
                let ext = format == .project ? "json" : format == .obj ? "zip" : format.rawValue
                exportType = UTType(filenameExtension: ext) ?? .data
                exportName = "Edited-design."+ext; exporting = true
            } catch is CancellationError { /* Cancellation produces no export or error alert. */ }
            catch { self.error = error.localizedDescription }
        }
    }
    private func importProject(_ result: Result<URL,Error>) {
        perform {
            let url = try result.get(),access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let imported = try SceneEditStore.read(url,source: session.document.source,id: session.document.sourceID) else { throw SceneEditDocument.Failure.invalid }
            try session.change { $0 = imported }; session.selectedID = nil; reset += 1
        }
    }
}

private struct StudioObjectFields: View {
    let item: SceneEditObject
    let catalogue: [SceneFurniture]
    let replace: (SceneFurniture) -> Void
    let update: (SceneEditObject) -> Void
    var body: some View {
        TextField("Name",text: field(\.name))
        Picker("Model",selection: Binding(get: { item.family },set: replace)) { ForEach(catalogue.contains(item.family) ? catalogue : catalogue+[item.family]) { Text($0.title).tag($0) } }
        HStack { number("X (m)",\.position.x); number("Y (m)",\.position.y); number("Z (m)",\.position.z) }
        HStack { number("Width (m)",\.size.x); number("Height / length (m)",\.size.y); number("Depth (m)",\.size.z) }
        TextField("Rotation (degrees)",value: Binding(get: { item.yaw*180 / .pi },set: { var next = item; next.yaw = $0 * .pi/180; update(next) }),format: .number)
        ColorPicker("Colour",selection: Binding(get: { Self.color(item.color) },set: { value in if let rgb = Self.rgb(value) { var next = item; next.color = rgb; next.colorSource = .user; update(next) } }),supportsOpacity: false)
        Text(item.colorSource == .cameraSample ? "Camera-sampled base colour; material finish unverified" : item.colorSource == .user ? "Custom design colour" : "Display preset · no captured colour").font(.caption2).foregroundStyle(.secondary)
        if let captured = item.capturedColor,item.colorSource != .cameraSample {
            Button("Restore captured colour") { var next = item; next.color = captured; next.colorSource = .cameraSample; update(next) }
        }
        Picker("Material",selection: field(\.finish)) { ForEach(SceneEditObject.Finish.allCases,id: \.self) { Text(AppLanguage.text($0.rawValue)).tag($0) } }
        Text(item.origin).font(.caption2).foregroundStyle(.secondary)
    }
    private func field<T>(_ path: WritableKeyPath<SceneEditObject,T>) -> Binding<T> { Binding(get: { item[keyPath: path] },set: { value in var next = item; next[keyPath: path] = value; update(next) }) }
    private func number(_ title: String,_ path: WritableKeyPath<SceneEditObject,Double>) -> some View {
        VStack(alignment: .leading,spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title,value: field(path),format: .number.precision(.fractionLength(0...3)))
                .accessibilityLabel(title)
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
        }
    }
    static func color(_ p: TechnicalPoint3) -> Color { Color(red: p.x,green: p.y,blue: p.z) }
    static func rgb(_ value: Color) -> TechnicalPoint3? {
        #if os(iOS)
        let color = UIColor(value)
        var r: CGFloat = 0,g: CGFloat = 0,b: CGFloat = 0,a: CGFloat = 0
        guard color.getRed(&r,green: &g,blue: &b,alpha: &a) else { return nil }
        #else
        guard let color = NSColor(value).usingColorSpace(.sRGB) else { return nil }
        let r = color.redComponent,g = color.greenComponent,b = color.blueComponent
        #endif
        return .init(x: Double(r),y: Double(g),z: Double(b))
    }
}

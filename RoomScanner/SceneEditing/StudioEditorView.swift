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
    @State private var error: String?
    var body: some View {
        Group {
            if let loaded { StudioEditorView(document: loaded,storageURL: SceneEditStore.url(root: storageRoot,source: seed.source,id: seed.sourceID)) }
            else if let error { ContentUnavailableView("Could not open design",systemImage: "exclamationmark.triangle",description: Text(error)) }
            else { ProgressView("Opening Studio…") }
        }
        .task {
            do {
                let url = SceneEditStore.url(root: storageRoot,source: seed.source,id: seed.sourceID)
                let document = try await Task.detached { try SceneEditStore.read(url,source: seed.source,id: seed.sourceID) ?? seed }.value
                try document.validate(); loaded = document
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct StudioEditorView: View {
    let storageURL: URL
    @State private var session: SceneEditSession
    @State private var controller = StudioSceneController()
    @State private var moving = false
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
    @State private var error: String?
    @State private var status = ""
    @State private var busy = false
    @State private var hasSaved = false
    @State private var exportFile: StudioFile?
    @State private var exportType = UTType.data
    @State private var exportName = "Design"
    @State private var exporting = false
    @State private var importing = false
    @State private var equipmentEditor: SceneEditObject?
    @State private var confirmClose = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    init(document: SceneEditDocument,storageURL: URL) {
        self.storageURL = storageURL
        _session = State(initialValue: SceneEditSession(document))
        _story = State(initialValue: document.shell.stories.first?.index ?? 0)
    }
    var body: some View {
        editorLayout
        .disabled(busy).allowsHitTesting(!busy)
        .navigationTitle(session.document.source == .technical ? "Technik Studio" : "House Studio")
        #if os(iOS)
        .toolbar(.hidden,for: .navigationBar)
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
            ToolbarItem(placement: .cancellationAction) { closeButton }
            ToolbarItem(placement: .automatic) { undoButton }
            ToolbarItem(placement: .automatic) { designOptions }
            ToolbarItem(placement: .confirmationAction) { saveButton }
        }
        #endif
        .tint(.blue)
        .onAppear {
            hasSaved = FileManager.default.fileExists(atPath: storageURL.path)
            controller.onSelect = { session.selectedID = $0 }
            controller.onMove = { id,position in
                guard var item = session.document.objects.first(where: { $0.id == id }) else { return false }
                item.position = position
                if snapping { item = StudioPlacement.snapped(item,in: session.document) }
                do { try update(item); return true } catch { self.error = error.localizedDescription; return false }
            }
        }
        .onDisappear { controller.onSelect = nil; controller.onMove = nil }
        .sheet(isPresented: Binding(get: { showEngineering && !inspectorPresentedModally },set: { showEngineering = $0 })) { StudioEngineeringView(session: session) }
        .onChange(of: story) { _,_ in session.selectedID = nil }
        .onChange(of: session.document.objects.map(\.id)) { _,ids in
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

    @ViewBuilder private var editorLayout: some View {
        #if os(iOS)
        ZStack {
            viewport.ignoresSafeArea()
            VStack(spacing: 0) {
                phoneHeader.padding(.horizontal,16).padding(.top,8)
                Spacer(minLength: 12)
                if !landscape {
                    VStack(spacing: 4) {
                        selectionHUD
                        if busy { ProgressView("Working…").padding(10).background(.regularMaterial,in: Capsule()) }
                        else if !status.isEmpty { Text(status).font(.caption).padding(10).background(.regularMaterial,in: Capsule()) }
                        phoneDock
                    }.padding(.horizontal,10).padding(.bottom,0)
                }
            }
            if landscape {
                HStack(alignment: .bottom,spacing: 12) {
                    phoneDock.frame(maxWidth: 520)
                    Spacer(minLength: 0)
                    if showInspector {
                        NavigationStack {
                            inspector.navigationTitle("Object properties")
                                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showInspector = false } } }
                        }.frame(width: min(310,canvasWidth*0.38)).background(.regularMaterial,in: RoundedRectangle(cornerRadius: 24)).clipShape(RoundedRectangle(cornerRadius: 24))
                            .sheet(item: $equipmentEditor) { item in equipmentSheet(item) }
                    }
                }.frame(maxWidth: .infinity,maxHeight: .infinity,alignment: .bottom)
                    .padding(.horizontal,10).padding(.top,76).padding(.bottom,0)
            }
        }
            .foregroundStyle(.primary)
        #else
        VStack(spacing: 0) {
            HStack {
                Picker("Interaction",selection: $moving) { Text("Orbit").tag(false); Text("Move objects").tag(true) }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 260)
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
            viewport
            if showInspector {
                inspector.frame(maxHeight: 270)
            }
            HStack {
                Text(busy ? "Working…" : status.isEmpty ? moving ? "Drag an object to move it. Changes are design edits." : "Tap furniture to select · drag to orbit · pinch to zoom" : status)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Text(session.dirty || !hasSaved ? "Unsaved design" : "Design saved").font(.caption).foregroundStyle(.secondary)
            }.padding(10)
        }
        #endif
    }
    private var phoneHeader: some View {
        VStack(alignment: .leading,spacing: 8) {
            if textSize.isAccessibilitySize {
                Text(session.document.source == .technical ? "Technik Studio" : "House Studio")
                    .font(.headline).padding(.horizontal,12).padding(.vertical,8)
                    .background(.regularMaterial,in: Capsule())
            }
            HStack(spacing: 12) {
                Button { requestClose() } label: { Image(systemName: "xmark").frame(width: 44,height: 44) }
                    .accessibilityLabel("Close Studio").background(.regularMaterial,in: Circle())
                if !textSize.isAccessibilitySize {
                    VStack(alignment: .leading,spacing: 2) {
                        Text(session.document.source == .technical ? "Technik Studio" : "House Studio").font(.headline)
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
        if let item = session.selected {
            HStack {
                VStack(alignment: .leading,spacing: 3) {
                    Text(item.name).font(.subheadline.bold())
                    Text("\(item.size.x,specifier: "%.2f") × \(item.size.y,specifier: "%.2f") × \(item.size.z,specifier: "%.2f") m").font(.caption).monospacedDigit()
                }
                Spacer()
                Button("Edit") { showInspector = true }.buttonStyle(.bordered)
            }.padding(.horizontal,12).padding(.vertical,6).background(.regularMaterial,in: RoundedRectangle(cornerRadius: 14))
        }
    }
    @ViewBuilder private var phoneDockActions: some View {
        Button { showModelLibrary = true } label: { dockLabel("Models",icon: "sofa.fill") }
        Button { moving.toggle() } label: { dockLabel(moving ? "Moving" : "Move",icon: "arrow.up.and.down.and.arrow.left.and.right") }.accessibilityValue(moving ? "On" : "Off")
        Button { showInspector.toggle() } label: { dockLabel("Edit",icon: "slider.horizontal.3") }
        Button { showAppearance = true } label: { dockLabel("Style",icon: "paintpalette") }
        Button { showDimensions.toggle() } label: { dockLabel("Sizes",icon: "ruler") }.accessibilityLabel("3D dimensions").accessibilityValue(showDimensions ? "On" : "Off")
        Menu { designActions } label: { dockLabel("More",icon: "ellipsis") }
    }
    @ViewBuilder private var viewport: some View {
        if showPlan { Plan2DView(house: House(id: session.document.shell.id,name: session.document.title,stories: session.document.plan.stories.filter { $0.index == story })) }
        else {
            StudioViewport(controller: controller,document: session.document,story: story,cutaway: cutaway,selected: session.selectedID,moving: moving && (session.document.engineering?.view == nil || session.document.engineering?.view == .all || session.document.engineering?.view == .proposed),reset: reset,showDimensions: showDimensions)
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
        return [.sofa,.bed,.chair,.table,.television,.cabinet,.refrigerator,.stove,.sink,.toilet,.bathtub,.shower,.washer,.radiator,.box,.cylinder]
    }
    private var modelMenu: some View { ForEach(catalogue) { family in Button(family.title) { add(family) } }.disabled(session.document.objects.count >= 500) }
    private var designOptions: some View {
        Menu { designActions } label: { Label("Design options",systemImage: "ellipsis.circle") }.disabled(busy)
    }
    @ViewBuilder private var designActions: some View {
                    undoButton
                    Button("Redo") { session.redo() }.disabled(session.redoStack.isEmpty)
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
                    Divider()
                    Menu("Add model") { modelMenu }
                    Button("Import design project…") { importing = true }
                    Menu("Export edited design") {
                        Button("PNG image · current view") { image() }.disabled(showPlan)
                        ForEach(StudioExporter.Format.allCases,id: \.self) { format in Button(format == .csv ? "Engineering register · CSV" : format == .project ? "Editable project · JSON" : format == .obj ? "OBJ + materials · current floor · ZIP" : format == .usdz ? "USDZ · current floor" : format.rawValue.uppercased()) { export(format) } }
                    }
    }
    private func dockLabel(_ title: String,icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 18,weight: .medium)).frame(height: 20)
            Text(title).font(.caption2.weight(.medium)).lineLimit(1)
        }.frame(maxWidth: .infinity,minHeight: 44).contentShape(Rectangle())
    }
    private var modelLibrary: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130),spacing: 12)],spacing: 12) {
                    ForEach(catalogue.filter { modelSearch.isEmpty || $0.title.localizedCaseInsensitiveContains(modelSearch) }) { family in
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
                Section("Interior") {
                  if session.document.source != .technical {
                    Picker("Style",selection: Binding(get: { session.document.interior },set: { value in perform { try session.change { $0.apply(value) } } })) {
                        ForEach(SceneEditDocument.Interior.allCases,id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                  }
                    ColorPicker("Walls",selection: colorBinding(wall: true),supportsOpacity: false)
                    ColorPicker("Floor",selection: colorBinding(wall: false),supportsOpacity: false)
                    if session.document.source != .technical {
                        Picker("Floor finish",selection: Binding(get: { session.document.floorFinish ?? .wood },set: { value in perform { try session.change { $0.floorFinish = value; $0.floorPatternSize = nil } } })) {
                            ForEach(SceneEditDocument.FloorFinish.allCases,id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }
                        if session.document.floorFinish != .plain {
                            Stepper("Pattern repeat: \((session.document.floorPatternSize ?? (session.document.floorFinish == .tile ? 0.3 : 0.72)).formatted()) m",value: Binding(get: { session.document.floorPatternSize ?? (session.document.floorFinish == .tile ? 0.3 : 0.72) },set: { value in perform { try session.change { $0.floorPatternSize = value } } }),in: 0.1...2,step: 0.05)
                            Text("Presentation pattern only; not a measured tile or board size.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if session.document.source != .technical { Section("Lighting and mood") {
                    Picker("Lighting",selection: Binding(get: { session.document.lighting },set: { value in perform { try session.change { $0.lighting = value } } })) {
                        ForEach(SceneEditDocument.Lighting.allCases,id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Picker("Season",selection: Binding(get: { session.document.season },set: { value in perform { try session.change { $0.season = value } } })) {
                        ForEach(SceneEditDocument.Season.allCases,id: \.self) { Text($0.rawValue.capitalized).tag($0) }
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
    private func save(close: Bool = false) {
        busy = true; let document = session.document
        Task { @MainActor in
            defer { busy = false }
            do {
                try await Task.detached { try SceneEditStore.write(document,to: storageURL) }.value
                session.markSaved(); hasSaved = true; status = "Design saved separately from the scan."
                if close { dismiss() }
            } catch { self.error = error.localizedDescription }
        }
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
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                exportFile = StudioFile(try StudioExporter.data(session.document,format: format,story: story))
                let ext = format == .project ? "json" : format == .obj ? "zip" : format.rawValue
                exportType = UTType(filenameExtension: ext) ?? .data
                exportName = "Edited-design."+ext; exporting = true
            } catch { self.error = error.localizedDescription }
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
        Picker("Material",selection: field(\.finish)) { ForEach(SceneEditObject.Finish.allCases,id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
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

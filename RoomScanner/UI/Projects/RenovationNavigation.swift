import SwiftUI
import ImageIO

#if os(iOS)
struct RenovationNavigation: View {
    var refreshToken = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(RoomStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var workspace = RenovationWorkspace()
    @State private var openProjectID: UUID?
    @State private var savedReference: ProjectReference?
    @State private var openingSavedScan = false
    @State private var settings = false
    @State private var scanRequest:ProjectScanRequest?
    @State private var pendingCapture: PreparedProjectCapture?
    @State private var activeCapture: PreparedProjectCapture?
    @State private var creating = false
    @State private var projectName = ""
    @State private var projectQuery = ""
    @AppStorage("ui.projects.newest") private var sortNewest = true
    @AppStorage("ui.projects.layout") private var projectLayout = "grid"
    @State private var renamingProject: RenovationProject?
    @State private var privacyProject: RenovationProject?
    @AppStorage("renovation.onboarded") private var onboarded = false
    @State private var guide = false
    @State private var guidePage = 0
    #if DEBUG && targetEnvironment(simulator)
    @State private var screenshotOpened = false
    @State private var screenshotGallery = false
    #endif

    var body: some View {
        Group {
            if let id = openProjectID {
                ProjectChatWorkspace(projectID:id,savedReference:$savedReference,onScan:beginScan,onCapture:{ mode in beginCapture(mode,projectID:id) },onClose:{ openProjectID = nil })
                    #if DEBUG && targetEnvironment(simulator)
                    .onAppear { ScreenshotDestination.dashboard.appeared() }
                    #endif
            } else {
                navigation { projects }
            }
        }
        .task(id:refreshToken) { await workspace.reload(location:store.location); guide = !onboarded }
        #if DEBUG && targetEnvironment(simulator)
        .onChange(of: workspace.catalogueRevision) {
            guard !screenshotOpened, let destination = ScreenshotDestination.requested,
                  let project = workspace.index.projects.first(where: { !$0.isUnsorted && $0.references.count == 2 }),
                  workspace.error == nil else { return }
            screenshotOpened = true
            switch destination {
            case .projects: destination.appeared()
            case .dashboard: openProjectID = project.id
            case .scanSetup: beginCapture(.house, projectID: project.id)
            case .gallery: screenshotGallery = true
            }
        }
        .sheet(isPresented: $screenshotGallery) {
            NavigationStack {
                DesignSystemGallery(dark: UserDefaults.standard.string(forKey: "ui.appearance") == "dark")
                    .onAppear { ScreenshotDestination.gallery.appeared() }
            }
        }
        #endif
        .onChange(of:store.records) { _,_ in refresh() }
        .onChange(of:store.houseRecords) { _,_ in refresh() }
        .onChange(of:scenePhase) { _,phase in if phase == .active { refresh() } }
        .onChange(of:store.location.documentsURL) { _,_ in refresh() }
        .sheet(isPresented:$settings,onDismiss:refresh) { SettingsView(includesProfile:true).environment(store) }
        .sheet(isPresented:$guide) { onboarding }
        .sheet(item:$privacyProject,onDismiss:refresh) { project in
            NavigationStack {
                ProjectPrivacyView(projectID:project.id).environment(store)
                    .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { privacyProject = nil } } }
            }
        }
        .sheet(item:$scanRequest,onDismiss:{ activeCapture = pendingCapture; pendingCapture = nil }) { request in
            ScanSetupSheet(workspace:workspace,projectID:request.projectID,mode:request.mode,defaultLocation:store.location) { pendingCapture = $0 }
                .id(request.id)
                .presentationDetents([.medium,.large])
                #if DEBUG && targetEnvironment(simulator)
                .onAppear { ScreenshotDestination.scanSetup.appeared() }
                #endif
        }
        .fullScreenCover(item:$activeCapture,onDismiss:refresh) { capture in
            ProjectCaptureView(mode:capture.mode,projectID:capture.projectID,store:store,workspace:workspace,preparedPersistence:capture.persistence,captureLocation:capture.location,onSaved:{ kind,id,library in
                attach(kind,id:id,library:library,projectID:capture.projectID,location:capture.location)
            })
        }
        .alert("New project",isPresented:$creating) {
            TextField("Project name",text:$projectName)
            Button("Create") { workspace.create(projectName); projectName = "" }
            Button("Cancel",role:.cancel) {}
        } message: { Text("A place, such as a flat or building address.") }
        .sheet(item:$renamingProject) { project in ProjectRenameSheet(project:project).environment(workspace) }
        .alert("Project library",isPresented:Binding(get:{ workspace.error != nil },set:{ if !$0 { workspace.error = nil } })) {
            Button("OK") { workspace.error = nil }
        } message: { Text(workspace.error ?? "") }
        .overlay {
            if openingSavedScan { ProgressView("Opening scan…").padding(20).dsMaterial(in:RoundedRectangle(cornerRadius:DS.Radius.floating)) }
        }
        .environment(workspace)
    }
    private func refresh() { Task { await workspace.reload(location:store.location) } }
    private func attach(_ kind: ProjectReference.Kind,id: UUID,library: String,projectID:UUID?,location:StorageLocation) {
        openingSavedScan = true
        Task {
            defer { openingSavedScan = false }
            await workspace.reloadAndWait(location:location)
            let reference = ProjectReference(kind:kind,itemID:id,library:library)
            if let projectID {
                workspace.assign(reference,to:projectID)
                guard workspace.project(projectID)?.references.contains(reference) == true else { return }
            }
            guard workspace.destination(reference) != nil else { return }
            openProjectID = projectID ?? workspace.index.projects.first(where:{ $0.references.contains(reference) })?.id
            savedReference = reference
        }
    }
    private func navigation<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .toolbar { ToolbarItem(placement:.topBarTrailing) {
                    Button { settings = true } label: { Label("Settings",systemImage:"person.crop.circle") }.labelStyle(.iconOnly)
                } }
                .navigationDestination(for:ProjectReference.self) { reference in
                    if let entry = workspace.destination(reference) { RenovationItemDestination(entry:entry) }
                    else { ContentUnavailableView("Item unavailable",systemImage:"icloud.slash",description:Text("Reconnect its library to open this item. Your project reference has been kept.")) }
                }
        }
    }
    private func beginCapture(_ mode:ScanMode,projectID:UUID) {
        workspace.currentProjectID = projectID
        scanRequest = ProjectScanRequest(projectID:projectID,mode:mode)
    }
    private func beginScan() { scanRequest = ProjectScanRequest(projectID:workspace.currentProjectID,mode:.house) }
    private var visibleProjects:[RenovationProject] {
        workspace.index.projects.filter {
            projectQuery.isEmpty || ($0.isUnsorted ? AppLanguage.text("Unsorted") : $0.name).localizedCaseInsensitiveContains(projectQuery)
        }.sorted {
            if sortNewest, $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.id.uuidString < $1.id.uuidString : comparison == .orderedAscending
        }
    }
    private var projects: some View {
        Group {
            if projectLayout == "list" {
                List {
                    ForEach(visibleProjects) { projectLink($0,card:false) }
                    if visibleProjects.isEmpty { projectEmptyState }
                }
            } else {
                ScrollView {
                    VStack(spacing:DS.Spacing.l) {
                            if visibleProjects.isEmpty { projectEmptyState }
                        LazyVGrid(columns:sizeClass == .compact ? [GridItem(.flexible()),GridItem(.flexible())] : [GridItem(.adaptive(minimum:200))],spacing:DS.Spacing.l) {
                            ForEach(visibleProjects) { projectLink($0,card:true) }
                        }
                    }.padding(DS.Spacing.l)
                }
            }
        }.navigationTitle("Projects").searchable(text:$projectQuery,prompt:"Search projects")
            .toolbar { ToolbarItemGroup(placement:.topBarLeading) {
                Button("New project",systemImage:"plus") { creating = true }.labelStyle(.iconOnly)
                Menu("View options",systemImage:"line.3.horizontal.decrease") {
                    Picker("Layout",selection:$projectLayout) { Label("Grid",systemImage:"square.grid.2x2").tag("grid"); Label("List",systemImage:"list.bullet").tag("list") }
                    Toggle("Newest first",isOn:$sortNewest)
                }
            } }
            .refreshable { await workspace.reload(location:store.location) }
    }
    private var projectEmptyState:some View {
        ContentUnavailableView {
            Label(LocalizedStringKey(projectQuery.isEmpty ? "Your projects" : "No matching projects"),systemImage:"folder")
        } description: { Text("Keep scans, designs and survey notes together.") }
        actions: { if projectQuery.isEmpty { Button("Create a project") { creating = true } } }
    }
    private func projectLink(_ project:RenovationProject,card:Bool) -> some View {
        Button { openProjectID = project.id } label: {
            ProjectSummary(project:project,workspace:workspace,card:card)
                .contentShape(Rectangle())
        }
            .accessibilityIdentifier("project.open.\(project.id.uuidString)")
            .buttonStyle(.plain)
            .contextMenu {
                if !project.isUnsorted {
                    Button("Rename",systemImage:"pencil") { renamingProject = project }
                }
                Button("Delete project data…",systemImage:"trash",role:.destructive) { privacyProject = project }
            }
    }
    private var onboarding: some View {
        NavigationStack {
            VStack(spacing:24) {
                Image(systemName:["folder","viewfinder","ruler"][guidePage]).dsIcon(.hero).accessibilityHidden(true)
                Text(LocalizedStringKey(["Create a project","Scan your space","Review and verify"][guidePage])).font(.title).multilineTextAlignment(.center)
                Text(LocalizedStringKey(["Group a building's scans, designs, photos and notes in one place.","Choose House or Technik room. Your original scan stays separate from design edits.","Check important dimensions before sharing a report. Capture-derived data is device validation pending."][guidePage])).multilineTextAlignment(.center)
                Button(guidePage == 2 ? "Get started" : "Next") { if guidePage < 2 { guidePage += 1 } else { onboarded = true; guide = false } }.dsProminentControl()
            }.padding(28).navigationTitle("Welcome")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Skip") { onboarded = true; guide = false } } }
        }.interactiveDismissDisabled()
    }
}


/// A presentation owns an explicit context; environment modifiers on the
/// presenting list do not supply dependencies to sibling full-screen covers.
struct ProjectCaptureView: View {
    let mode: ScanMode
    let projectID: UUID?
    @State private var store: RoomStore
    let workspace: RenovationWorkspace
    var preparedPersistence: CapturePersistence? = nil
    let onSaved: (ProjectReference.Kind,UUID,String) -> Void
    init(mode:ScanMode,projectID:UUID?,store:RoomStore,workspace:RenovationWorkspace,preparedPersistence:CapturePersistence? = nil,captureLocation:StorageLocation? = nil,onSaved:@escaping (ProjectReference.Kind,UUID,String)->Void) {
        self.mode = mode; self.projectID = projectID; self.workspace = workspace
        self.preparedPersistence = preparedPersistence; self.onSaved = onSaved
        if let captureLocation,captureLocation != store.location {
            let scoped = RoomStore(location:captureLocation,allowsCloud:false); scoped.reload()
            _store = State(initialValue:scoped)
        } else { _store = State(initialValue:store) }
    }
    var body: some View {
        Group {
            if mode == .technicalRoom {
                TechnicalRoomScanView(voiceProjectID:projectID,workspace:workspace,preparedPersistence:preparedPersistence,onSaved:{ onSaved(.technicalRoom,$0,"local") })
            } else {
                ScanView(mode:mode,voiceProjectID:projectID,workspace:workspace,preparedPersistence:preparedPersistence,onSaved:{ onSaved(mode == .house ? .house : .room,$0.id,store.isCloud ? "icloud" : "local") })
            }
        }
        .environment(store)
        .environment(workspace)
        .projectPreferenceScope(projectID.map { workspace.project($0)?.details?.preferences ?? .init() })
    }
}


#endif

struct ProjectSummary: View {
    let project: RenovationProject
    let workspace: RenovationWorkspace
    var card = false
    private var primary: ProjectLibraryEntry? {
        let entries = project.references.compactMap(workspace.entry).sorted { $0.date > $1.date }
        return entries.first { $0.reference.kind == .house } ?? entries.first { $0.reference.kind == .room }
    }
    var body: some View {
        Group {
            if card {
                VStack(alignment:.leading,spacing:10) { cover; labels }
                    .padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.secondary.opacity(0.08),in:RoundedRectangle(cornerRadius:DS.Radius.project))
            } else { HStack { cover; labels } }
        }
    }
    private var cover:some View { ProjectCover(url:primary?.url.appendingPathComponent("thumbnail.png"),size:card ? 140 : 72) }
    private var labels:some View {
            VStack(alignment:.leading) {
                Text(project.isUnsorted ? AppLanguage.text("Unsorted") : project.name).font(.headline)
                Text(String(project.references.count)+" "+AppLanguage.text("Scans & designs")).font(.subheadline).foregroundStyle(.secondary)
                Text(project.modifiedAt,style:.date).font(.caption2).foregroundStyle(.tertiary)
                if let primary,let area = primary.area {
                    Text(AppLanguage.text("Primary plan")+": "+String(primary.roomCount)+" · "+MeasurementFormat.squareMeters(area)).font(.caption).foregroundStyle(.secondary)
                }
            }
    }
}

struct ProjectCover: View {
    @Environment(\.colorScheme) private var colorScheme
    let url: URL?
    var size:CGFloat = 72
    var technicalPackageURL:URL? = nil
    @State private var image: CGImage?
    var body: some View {
        Group {
            if let image {
                if technicalPackageURL == nil,colorScheme == .dark { Image(decorative:image,scale:1).resizable().scaledToFit().colorInvert() }
                else { Image(decorative:image,scale:1).resizable().scaledToFit() }
            }
            else { Image(systemName:"square.split.bottomrightquarter").font(.title2).foregroundStyle(.secondary) }
        }.frame(maxWidth:size).frame(height:size).background(technicalPackageURL == nil ? (colorScheme == .dark ? Color.black : Color.white) : DS.ColorToken.card.color,in:RoundedRectangle(cornerRadius:DS.Radius.small))
            .task(id:url) {
                image = nil
                if let technicalPackageURL,let mesh = try? await TechnicalMeshPreviewCache.shared.image(packageURL:technicalPackageURL) {
                    guard !Task.isCancelled else { return }; image = mesh; return
                }
                guard let url else { return }
                let decoded = await Task.detached {
                    guard let source = CGImageSourceCreateWithURL(url as CFURL,nil) else { return nil as CGImage? }
                    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:256] as CFDictionary) else { return nil }
                    guard let gray = CGContext(data:nil,width:thumbnail.width,height:thumbnail.height,bitsPerComponent:8,bytesPerRow:thumbnail.width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue) else { return thumbnail }
                    gray.draw(thumbnail,in:CGRect(x:0,y:0,width:thumbnail.width,height:thumbnail.height))
                    return gray.makeImage()
                }.value
                guard !Task.isCancelled else { return }
                image = decoded
            }
    }
}

struct ProjectEntryRow: View {
    let entry: ProjectLibraryEntry
    var openAsDesign = false
    var card = false
    @Environment(RenovationWorkspace.self) private var workspace
    @Environment(\.locale) private var locale
    @State private var renaming = false
    @State private var organizing = false
    @State private var exporting = false
    @State private var removing = false
    @State private var name = ""
    var body: some View {
        NavigationLink(value:openAsDesign ? designReference : entry.reference) {
            if card {
                VStack(alignment:.leading,spacing:8) {
                    if openAsDesign || entry.isDesign { ProjectStudioCover(entry:entry) }
                    else { ProjectCover(url:coverURL,size:160,technicalPackageURL:entry.reference.kind == .technicalRoom ? entry.url : nil).frame(maxWidth:.infinity) }
                    Text(workspace.title(entry,locale:locale)).font(.headline).lineLimit(2)
                    Text(String(entry.roomCount)+" "+AppLanguage.text("Rooms")).font(.caption).foregroundStyle(.secondary)
                    if let area = entry.area { Text(MeasurementFormat.squareMeters(area)).font(.caption).foregroundStyle(.secondary) }
                    Text(entry.date,style:.date).font(.caption2).foregroundStyle(.tertiary)
                }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.secondary.opacity(0.08),in:RoundedRectangle(cornerRadius:DS.Radius.project))
            } else {
            HStack {
                Image(systemName:entry.isDesign ? "square.stack.3d.up" : entry.reference.kind == .technicalRoom ? "wrench.and.screwdriver" : "house")
                VStack(alignment:.leading) { Text(workspace.title(entry,locale:locale)); Text(entry.date,style:.date).font(.caption).foregroundStyle(.secondary) }
            }
            }
        }
        .contextMenu {
            if !entry.isDesign {
                Button("Export",systemImage:"square.and.arrow.up") { exporting = true }
                if let project = workspace.index.projects.first(where:{ $0.references.contains(entry.reference) }) {
                    NavigationLink { ProjectQuantitiesView(projectID:project.id,reference:entry.reference) } label: { Label("Measurement report",systemImage:"ruler") }
                }
            }
            if !entry.isDesign { Button("Edit organization",systemImage:"building.2") { organizing = true } }
            Button("Rename") { name = workspace.title(entry,locale:locale); renaming = true }
            Button("Duplicate") { Task { await workspace.duplicate(entry) } }
            NavigationLink("Open in Studio",value:designReference)
            Menu("Move to project") { ForEach(workspace.index.projects) { project in Button(project.isUnsorted ? AppLanguage.text("Unsorted") : project.name) { workspace.assign(entry.reference,to:project.id) } } }
            ShareLink(item:entry.url) { Label("Share",systemImage:"square.and.arrow.up") }
            Button("Remove saved item",systemImage:"trash",role:.destructive) { removing = true }
        }
        .alert("Rename",isPresented:$renaming) {
            TextField("Name",text:$name)
            Button("Save") { workspace.rename(entry,to:name) }
            Button("Cancel",role:.cancel) {}
        } message: { Text("This name is stored in the project index. The original scan stays unchanged.") }
        .sheet(isPresented:$organizing) {
            ScanOrganizationEditor(entry:entry,organization:workspace.index.scanOrganization?[entry.id]).environment(workspace)
        }
        .sheet(isPresented:$exporting) {
            ProjectScanExportSheet(entry:workspace.localizedEntry(entry,locale:locale))
                .environment(RoomStore(location:.init(kind:entry.reference.library == "icloud" ? .iCloud : .local,documentsURL:entry.root),allowsCloud:false))
                .projectPreferenceScope(workspace.index.projects.first(where:{ $0.references.contains(entry.reference) })?.details?.preferences)
        }
        .confirmationDialog("Remove saved item?",isPresented:$removing,titleVisibility:.visible) {
            Button("Remove saved item",role:.destructive) { Task { await workspace.remove(entry) } }
            Button("Cancel",role:.cancel) {}
        } message: { Text("The item and its packaged photos leave the library. Project notes and shared exports remain. Source scans required by Studio designs are protected.") }
    }
    private var coverURL:URL {
        if !entry.isDesign { return entry.url.appendingPathComponent("thumbnail.png") }
        let location = StorageLocation(kind:.local,documentsURL:entry.root)
        let source = entry.reference.kind == .designHouse ? location.housePackageURL(for:entry.reference.itemID) : entry.reference.kind == .designRoom ? location.packageURL(for:entry.reference.itemID) : entry.root.appendingPathComponent("TechnicalRooms/\(entry.reference.itemID.uuidString).technicalroom")
        return source.appendingPathComponent("thumbnail.png")
    }
    private var designReference: ProjectReference { .init(kind:entry.reference.kind == .house ? .designHouse : entry.reference.kind == .room ? .designRoom : entry.isDesign ? entry.reference.kind : .designTechnical,itemID:entry.reference.itemID,library:entry.reference.library) }
}

#if os(iOS)
/// A project owns independent navigation stacks for its five working areas.
struct ProjectChatWorkspace: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(RoomStore.self) private var store
    @Environment(RenovationWorkspace.self) private var workspace
    let projectID: UUID
    @Binding var savedReference: ProjectReference?
    @State private var selectedTab = 0
    @State private var paths = (0..<5).map { _ in NavigationPath() }
    var onScan: () -> Void
    var onCapture: (ScanMode) -> Void
    var onClose: () -> Void
    private var entries: [ProjectLibraryEntry] {
        workspace.project(projectID)?.references.compactMap(workspace.entry) ?? []
    }
    var body: some View {
        TabView(selection:$selectedTab) {
            Tab("Project", systemImage: "building.2", value:0) {
                projectStack("Project",index:0) { RenovationProjectPage(projectID: projectID, onScan: startScan) }
            }
            Tab("House", systemImage: "house", value:1) {
                projectStack("House",index:1) { scanCards(mode: .house) }
            }
            Tab("Technik", systemImage: "wrench.and.screwdriver", value:2) {
                projectStack("Technik",index:2) { scanCards(mode: .technicalRoom) }
            }
            Tab("Studio", systemImage: "cube.transparent", value:3) {
                projectStack("Studio",index:3) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: DS.Spacing.l) {
                            Text("Saved Studio designs").font(.headline); cards(entries.filter(\.isDesign))
                            cards(entries.filter { !$0.isDesign }, studio: true)
                        }.padding(DS.Spacing.l)
                    }
                }
            }
            Tab("Settings", systemImage: "gearshape", value:4) {
                projectStack("Settings",index:4) { ProjectDetailsEditor(projectID: projectID, settings: true) }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .onAppear { workspace.currentProjectID = projectID }
        .onChange(of:savedReference,initial:true) { _,reference in
            guard let reference else { return }
            selectedTab = reference.kind == .technicalRoom ? 2 : 1
            paths[selectedTab] = NavigationPath([reference])
            savedReference = nil
        }
        .projectPreferenceScope(workspace.project(projectID)?.details?.preferences ?? .init())
    }
    private func projectStack<Content: View>(_ title: LocalizedStringKey,index:Int, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack(path:$paths[index]) {
            content()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Projects", systemImage: "chevron.left", action:onClose) }
                }
                .navigationDestination(for: ProjectReference.self) { reference in
                    if let entry = workspace.destination(reference) { RenovationItemDestination(entry: entry) }
                    else { ContentUnavailableView("Item unavailable", systemImage: "icloud.slash", description: Text("Reconnect its library to open this item. Your project reference has been kept.")) }
                }
        }
    }
    private func cards(_ values: [ProjectLibraryEntry], studio: Bool = false) -> some View {
        LazyVGrid(columns: sizeClass == .compact ? [GridItem(.flexible()), GridItem(.flexible())] : [GridItem(.adaptive(minimum: 180))], spacing: DS.Spacing.l) {
            ForEach(values) { ProjectEntryRow(entry: $0, openAsDesign: studio, card: true).buttonStyle(.plain) }
        }
    }
    private func scanCards(mode: ScanMode) -> some View {
        ProjectScanLibraryView(projectID:projectID,technical:mode == .technicalRoom,onScan:{ onCapture(mode) })
    }
    private func startScan() { workspace.currentProjectID = projectID; onScan() }
}

#endif

struct RenovationItemDestination: View {
    let entry: ProjectLibraryEntry
    @Environment(RenovationWorkspace.self) private var workspace
    @Environment(RoomStore.self) private var libraryStore
    @State private var libraryLoaded = false
    @State private var itemStore: RoomStore
    @State private var design: SceneEditDocument?
    @State private var error: String?
    init(entry: ProjectLibraryEntry) {
        self.entry = entry
        _itemStore = State(initialValue:RoomStore(location:.init(kind:entry.reference.library == "icloud" ? .iCloud : .local,documentsURL:entry.root),allowsCloud:false))
    }
    var body: some View {
        Group {
            if let error { ContentUnavailableView(error,systemImage:"exclamationmark.triangle") }
            else if let design { StudioProjectView(seed:design,storageRoot:entry.root) }
            else if entry.isDesign { ProgressView("Opening design…") }
            else if !libraryLoaded { ProgressView("Opening scan…") }
            else if entry.reference.kind == .house, let r = itemStore.houseRecords.first(where:{ $0.id == entry.reference.itemID }) { HouseDetailView(record:r).environment(itemStore) }
            else if entry.reference.kind == .room, let r = itemStore.records.first(where:{ $0.id == entry.reference.itemID }) { RoomDetailView(record:r).environment(itemStore) }
            else if entry.reference.kind == .technicalRoom { TechnicalStoredRoomView(id:entry.reference.itemID,library:TechnicalRoomLibraryStore(root:entry.root.appendingPathComponent("TechnicalRooms"))) }
            else { ContentUnavailableView("Item unavailable",systemImage:"folder.badge.questionmark") }
        }.onDisappear { Task { await workspace.reload(location:libraryStore.location) } }.task {
            guard entry.isDesign else {
                if entry.reference.kind != .technicalRoom { itemStore.reload() }
                libraryLoaded = true
                return
            }
            do {
                design = try await Task.detached {
                    let source: SceneEditDocument.Source = entry.reference.kind == .designHouse ? .house : entry.reference.kind == .designRoom ? .room : .technical
                    if let saved = try SceneEditStore.read(SceneEditStore.url(root:entry.root,source:source,id:entry.reference.itemID),source:source,id:entry.reference.itemID) { return saved }
                    if source == .technical { return try SceneEditDocument.technical(TechnicalRoomPackage.read(from:entry.url)) }
                    if source == .house {
                        var value = SceneEditDocument.seed(house:try HousePackage.readHouse(from:entry.url),source:.house,id:entry.reference.itemID,scans:try HousePackage.readStructure(from:entry.url)?.rooms ?? [])
                        value.includeRadiators(try HousePackage.readRadiators(from:entry.url)?.radiators ?? []); return value
                    }
                    return .seed(house:House(room:try RoomPackage.readPlan(from:entry.url)),source:.room,id:entry.reference.itemID,scans:try RoomPackage.readScan(from:entry.url).map { [$0] } ?? [])
                }.value
            } catch { self.error = error.localizedDescription }
        }
    }
}

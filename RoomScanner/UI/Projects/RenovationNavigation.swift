import SwiftUI
import ImageIO

#if os(iOS)
struct RenovationNavigation: View {
    var refreshToken = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(RoomStore.self) private var store
    @State private var workspace = RenovationWorkspace()
    @State private var tab = Destination.home
    @State private var settings = false
    @State private var scan = false
    @State private var scanMode: ScanMode?
    @State private var requestedScan: ScanMode?
    @State private var creating = false
    @State private var projectName = ""
    @State private var projectQuery = ""
    @State private var searchQuery = ""
    @State private var sortNewest = true
    @State private var activeCaptureProject: UUID?
    @AppStorage("renovation.onboarded") private var onboarded = false
    @State private var guide = false
    @State private var guidePage = 0
    enum Destination: Hashable { case home, projects, design, search }

    var body: some View {
        TabView(selection:$tab) {
            navigation { home }.tabItem { Label("Home",systemImage:"house") }.tag(Destination.home)
            navigation { projects }.tabItem { Label("Projects",systemImage:"folder") }.tag(Destination.projects)
            navigation { designLibrary }.tabItem { Label("Design",systemImage:"square.stack.3d.up") }.tag(Destination.design)
            navigation { search }.tabItem { Label("Search",systemImage:"magnifyingglass") }.tag(Destination.search)
        }
        .modifier(ProjectScanAccessory(accessory:scanAccessory))
        .environment(workspace)
        .task(id:refreshToken) { await workspace.reload(location:store.location); guide = !onboarded }
        .onChange(of:store.records) { _,_ in refresh() }
        .onChange(of:store.houseRecords) { _,_ in refresh() }
        .onChange(of:scenePhase) { _,phase in if phase == .active { refresh() } }
        .onChange(of:store.location.documentsURL) { _,_ in refresh() }
        .sheet(isPresented:$settings,onDismiss:refresh) { SettingsView(includesProfile:true).environment(store) }
        .sheet(isPresented:$guide) { onboarding }
        .sheet(isPresented:$scan,onDismiss:{ if let requestedScan { self.requestedScan = nil; scanMode = requestedScan } }) { scanChoices.presentationDetents([.medium,.large]) }
        .fullScreenCover(item:$scanMode,onDismiss:refresh) { mode in
            if mode == .technicalRoom { TechnicalRoomScanView(onSaved:{ id in attach(.technicalRoom,id:id,library:"local") }) }
            else { ScanView(mode:mode,onSaved:{ item in attach(mode == .house ? .house : .room,id:item.id,library:store.isCloud ? "icloud" : "local") }).environment(store) }
        }
        .alert("New project",isPresented:$creating) {
            TextField("Project name",text:$projectName)
            Button("Create") { workspace.create(projectName); projectName = ""; tab = .projects }
            Button("Cancel",role:.cancel) {}
        } message: { Text("A place, such as a flat or building address.") }
        .alert("Project library",isPresented:Binding(get:{ workspace.error != nil },set:{ if !$0 { workspace.error = nil } })) {
            Button("OK") { workspace.error = nil }
        } message: { Text(workspace.error ?? "") }
    }
    private func refresh() { Task { await workspace.reload(location:store.location) } }
    private func attach(_ kind: ProjectReference.Kind,id: UUID,library: String) {
        let projectID = activeCaptureProject
        Task {
            await workspace.reload(location:store.location)
            if let projectID { workspace.assign(.init(kind:kind,itemID:id,library:library),to:projectID) }
        }
    }
    private func navigation<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .toolbar { ToolbarItem(placement:.topBarTrailing) {
                    Button { settings = true } label: { Label("Settings",systemImage:"person.crop.circle") }.labelStyle(.iconOnly)
                } }
                .navigationDestination(for:UUID.self) { id in RenovationProjectPage(projectID:id,onScan:beginScan) }
                .navigationDestination(for:ProjectReference.self) { reference in
                    if let entry = workspace.destination(reference) { RenovationItemDestination(entry:entry) }
                    else { ContentUnavailableView("Item unavailable",systemImage:"icloud.slash",description:Text("Reconnect its library to open this item. Your project reference has been kept.")) }
                }
        }
    }
    private func beginScan() { activeCaptureProject = workspace.currentProjectID; scan = true }
    private var scanAccessory: some View {
        HStack {
            Menu {
                ForEach(workspace.index.projects) { project in Button(project.isUnsorted ? AppLanguage.text("Unsorted") : project.name) { workspace.currentProjectID = project.id } }
                Button("New project") { creating = true }
            } label: { Label(workspace.currentProject.map { $0.isUnsorted ? AppLanguage.text("Unsorted") : $0.name } ?? AppLanguage.text("Choose a project"),systemImage:"folder") }
            .lineLimit(1)
            Spacer()
            Button("Scan",systemImage:"viewfinder",action:beginScan).buttonStyle(.borderedProminent)
        }.padding(.horizontal).padding(.vertical,8).background(.regularMaterial)
    }
    private var home: some View {
        List {
            Section("Continue") {
                ForEach(workspace.index.projects.filter { !$0.isUnsorted }.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(4)) { project in
                    NavigationLink(value:project.id) { ProjectSummary(project:project,workspace:workspace) }
                }
                if workspace.index.projects.allSatisfy(\.isUnsorted) { Button("Create a project",systemImage:"plus") { creating = true } }
            }
            Section("Recently scanned") { ForEach(workspace.entries.filter { !$0.isDesign }.prefix(5)) { entry in ProjectEntryRow(entry:entry) } }
            Section("Start a survey") { Button("Scan",systemImage:"viewfinder",action:beginScan) }
            Section("Tips") {
                Label("Move slowly and include corners, floor and ceiling.",systemImage:"viewfinder")
                Label("Check important dimensions with a tape measure.",systemImage:"ruler")
                Label("Keep photos and notes with the project.",systemImage:"camera")
            }.font(.callout)
        }.navigationTitle("Home").refreshable { await workspace.reload(location:store.location) }
    }
    private var projects: some View {
        List {
            if workspace.index.projects.isEmpty { ContentUnavailableView { Label("Your projects",systemImage:"folder") } description: { Text("Keep scans, designs and survey notes together.") } actions: { Button("Create a project") { creating = true } } }
            ForEach(workspace.index.projects.filter { projectQuery.isEmpty || ($0.isUnsorted ? AppLanguage.text("Unsorted") : $0.name).localizedCaseInsensitiveContains(projectQuery) }.sorted { sortNewest ? $0.modifiedAt > $1.modifiedAt : $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { project in
                NavigationLink(value:project.id) { ProjectSummary(project:project,workspace:workspace) }
            }
        }.navigationTitle("Projects").searchable(text:$projectQuery,prompt:"Search projects")
            .toolbar { ToolbarItemGroup(placement:.topBarLeading) {
                Button("New project",systemImage:"plus") { creating = true }.labelStyle(.iconOnly)
                Menu("Sort",systemImage:"arrow.up.arrow.down") { Toggle("Newest first",isOn:$sortNewest) }
            } }
            .refreshable { await workspace.reload(location:store.location) }
    }
    private var search: some View {
        List {
            ForEach(workspace.entries.filter { searchQuery.isEmpty || workspace.title($0).localizedCaseInsensitiveContains(searchQuery) }) { entry in ProjectEntryRow(entry:entry) }
        }.navigationTitle("Search").searchable(text:$searchQuery,prompt:"Search scans and designs")
    }
    private var designLibrary: some View {
        List {
            Section("Saved designs") {
                ForEach(workspace.entries.filter(\.isDesign)) { entry in ProjectEntryRow(entry:entry) }
            }
            Section("Start from a scan") {
                ForEach(workspace.entries.filter { !$0.isDesign }) { entry in ProjectEntryRow(entry:entry,openAsDesign:true) }
                if workspace.entries.isEmpty {
                    ContentUnavailableView { Label("No source scans yet",systemImage:"square.stack.3d.up") } description: { Text("Scan a room or import a saved scan before creating a design.") } actions: { Button("Scan",action:beginScan) }
                }
            }
        }.navigationTitle("Design").refreshable { await workspace.reload(location:store.location) }
    }
    private var scanChoices: some View {
        NavigationStack {
            List {
                Section("Scan") {
                    scanChoice(.house,"Whole home","house")
                    scanChoice(.room,"Room","square.dashed")
                    scanChoice(.technicalRoom,"Utility room","wrench.and.screwdriver")
                }
                Section("Before you start") {
                    Text("Use good light. Clear access to walls and installations. Move slowly and avoid reflective surfaces.")
                    Text("Device validation pending. Verify critical dimensions independently.").font(.caption)
                    if !ScanCoordinator.isSupported { Text("LiDAR capture is unavailable on this device. You can still open saved projects and designs.") }
                }
            }.navigationTitle("New scan").toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { scan = false } } }
        }
    }
    private func scanChoice(_ mode: ScanMode,_ name: LocalizedStringKey,_ icon: String) -> some View {
        Button { requestedScan = mode; scan = false } label: { Label(name,systemImage:icon) }.disabled(!ScanCoordinator.isSupported)
    }
    private var onboarding: some View {
        NavigationStack {
            VStack(spacing:24) {
                Image(systemName:["folder","viewfinder","ruler"][guidePage]).font(.system(size:64)).accessibilityHidden(true)
                Text(LocalizedStringKey(["Create a project","Scan your space","Review and verify"][guidePage])).font(.title).multilineTextAlignment(.center)
                Text(LocalizedStringKey(["Group a building's scans, designs, photos and notes in one place.","Choose Whole home, Room or Utility room. Your original scan stays separate from design edits.","Check important dimensions before sharing a report. Capture-derived data is device validation pending."][guidePage])).multilineTextAlignment(.center)
                Button(guidePage == 2 ? "Get started" : "Next") { if guidePage < 2 { guidePage += 1 } else { onboarded = true; guide = false } }.buttonStyle(.borderedProminent)
            }.padding(28).navigationTitle("Welcome")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Skip") { onboarded = true; guide = false } } }
        }.interactiveDismissDisabled()
    }
}

private struct ProjectScanAccessory<Accessory: View>: ViewModifier {
    let accessory: Accessory
    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.tabViewBottomAccessory { accessory }
        } else {
            content.safeAreaInset(edge:.bottom,spacing:0) { accessory }
        }
        #else
        content.safeAreaInset(edge:.bottom,spacing:0) { accessory }
        #endif
    }
}
#endif

struct ProjectSummary: View {
    let project: RenovationProject
    let workspace: RenovationWorkspace
    private var primary: ProjectLibraryEntry? {
        let entries = project.references.compactMap(workspace.entry).sorted { $0.date > $1.date }
        return entries.first { $0.reference.kind == .house } ?? entries.first { $0.reference.kind == .room }
    }
    var body: some View {
        HStack {
            ProjectCover(url:project.references.compactMap { workspace.entry($0)?.url.appendingPathComponent("thumbnail.png") }.first)
            VStack(alignment:.leading) {
                Text(project.isUnsorted ? AppLanguage.text("Unsorted") : project.name).font(.headline)
                Text(AppLanguage.text("Items")+": "+String(project.references.count)).font(.caption).foregroundStyle(.secondary)
                if let primary,let area = primary.area {
                    Text(AppLanguage.text("Primary plan")+": "+String(primary.roomCount)+" · "+MeasurementFormat.squareMeters(area)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ProjectCover: View {
    let url: URL?
    @State private var image: CGImage?
    var body: some View {
        Group {
            if let image { Image(decorative:image,scale:1).resizable().scaledToFit() }
            else { Image(systemName:"square.split.bottomrightquarter").font(.title2).foregroundStyle(.secondary) }
        }.frame(width:72,height:72).background(.quaternary,in:RoundedRectangle(cornerRadius:8))
            .task(id:url) {
                image = nil
                guard let url else { return }
                image = await Task.detached {
                    guard let source = CGImageSourceCreateWithURL(url as CFURL,nil) else { return nil as CGImage? }
                    return CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:256] as CFDictionary)
                }.value
            }
    }
}

struct ProjectEntryRow: View {
    let entry: ProjectLibraryEntry
    var openAsDesign = false
    @Environment(RenovationWorkspace.self) private var workspace
    @State private var renaming = false
    @State private var name = ""
    var body: some View {
        NavigationLink(value:openAsDesign ? designReference : entry.reference) {
            HStack {
                Image(systemName:entry.isDesign ? "square.stack.3d.up" : entry.reference.kind == .technicalRoom ? "wrench.and.screwdriver" : "house")
                VStack(alignment:.leading) { Text(workspace.title(entry)); Text(entry.date,style:.date).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .contextMenu {
            Button("Rename") { name = workspace.title(entry); renaming = true }
            Button("Duplicate") { Task { await workspace.duplicate(entry) } }
            NavigationLink("Open in Design",value:designReference)
            Menu("Move to project") { ForEach(workspace.index.projects) { project in Button(project.isUnsorted ? AppLanguage.text("Unsorted") : project.name) { workspace.assign(entry.reference,to:project.id) } } }
            ShareLink(item:entry.url) { Label("Share",systemImage:"square.and.arrow.up") }
        }
        .alert("Rename",isPresented:$renaming) {
            TextField("Name",text:$name)
            Button("Save") { workspace.rename(entry,to:name) }
            Button("Cancel",role:.cancel) {}
        } message: { Text("This name is stored in the project index. The original scan stays unchanged.") }
    }
    private var designReference: ProjectReference { .init(kind:entry.reference.kind == .house ? .designHouse : entry.reference.kind == .room ? .designRoom : entry.isDesign ? entry.reference.kind : .designTechnical,itemID:entry.reference.itemID,library:entry.reference.library) }
}

struct RenovationProjectPage: View {
    let projectID: UUID
    var onScan: () -> Void
    @Environment(RenovationWorkspace.self) private var workspace
    @State private var name = ""
    @State private var rename = false
    @State private var notes = ""
    var body: some View {
        List {
            if let project = workspace.project(projectID) {
                Section {
                    ProjectSummary(project:project,workspace:workspace)
                    Button("Scan more",systemImage:"viewfinder") { workspace.currentProjectID = projectID; onScan() }
                }
                if !project.references.isEmpty { Section("Preview") { ProjectScanPreview(entries:project.references.compactMap(workspace.entry)) } }
                Section("Scans") { ForEach(project.references.compactMap(workspace.entry).filter { !$0.isDesign }) { ProjectEntryRow(entry:$0) } }
                Section("Designs") { ForEach(project.references.compactMap(workspace.entry).filter(\.isDesign)) { ProjectEntryRow(entry:$0) } }
                Section("Exports") { NavigationLink("Project report and exports") { ProjectDeliverablesView(projectID:projectID) } }
                Section("Measurements") {
                    NavigationLink("Quantities") { ProjectQuantitiesView(projectID:projectID) }
                    NavigationLink("Verify with a known distance") { ProjectVerificationView(projectID:projectID) }
                }
                Section("Photos & notes") {
                    NavigationLink("Photos") { ProjectPhotosView(projectID:projectID) }
                    NavigationLink("Notes & task pins") { ProjectPinsView(projectID:projectID) }
                    TextEditor(text:$notes).frame(minHeight:100).accessibilityLabel("Project notes")
                    Button("Save notes") { workspace.note(notes,projectID:projectID) }
                }
                Section("Unavailable items") {
                    ForEach(project.references.filter { workspace.entry($0) == nil }) { ref in Label(ref.itemID.uuidString,systemImage:"icloud.slash").font(.caption) }
                }
            }
        }
        .navigationTitle(workspace.project(projectID).map { $0.isUnsorted ? AppLanguage.text("Unsorted") : $0.name } ?? AppLanguage.text("Project"))
        .onAppear { notes = workspace.project(projectID)?.notes ?? ""; workspace.currentProjectID = projectID }
        .toolbar { ToolbarItem { Menu("Project",systemImage:"ellipsis.circle") {
            Button("Rename") { name = workspace.project(projectID)?.name ?? ""; rename = true }.disabled(workspace.project(projectID)?.isUnsorted == true)
        } } }
        .alert("Rename project",isPresented:$rename) {
            TextField("Project name",text:$name)
            Button("Save") { workspace.change { index in if let i = index.projects.firstIndex(where:{ $0.id == projectID }), !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { index.projects[i].name = name; index.projects[i].isUnsorted = false; index.projects[i].modifiedAt = Date() } } }
            Button("Cancel",role:.cancel) {}
        }
    }
}

struct RenovationItemDestination: View {
    let entry: ProjectLibraryEntry
    @Environment(RenovationWorkspace.self) private var workspace
    @Environment(RoomStore.self) private var libraryStore
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
            else if entry.reference.kind == .house, let r = itemStore.houseRecords.first(where:{ $0.id == entry.reference.itemID }) { HouseDetailView(record:r).environment(itemStore) }
            else if entry.reference.kind == .room, let r = itemStore.records.first(where:{ $0.id == entry.reference.itemID }) { RoomDetailView(record:r).environment(itemStore) }
            else if entry.reference.kind == .technicalRoom { TechnicalStoredRoomView(id:entry.reference.itemID,library:TechnicalRoomLibraryStore(root:entry.root.appendingPathComponent("TechnicalRooms"))) }
            else { ContentUnavailableView("Item unavailable",systemImage:"folder.badge.questionmark") }
        }.onDisappear { Task { await workspace.reload(location:libraryStore.location) } }.task {
            guard entry.isDesign else { return }
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

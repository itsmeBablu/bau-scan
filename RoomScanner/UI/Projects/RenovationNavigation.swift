import SwiftUI
import ImageIO

#if os(iOS)
struct RenovationNavigation: View {
    var refreshToken = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(RoomStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var workspace = RenovationWorkspace()
    @State private var settings = false
    @State private var scan = false
    @State private var scanMode: ScanMode?
    @State private var requestedScan: ScanMode?
    @State private var creating = false
    @State private var projectName = ""
    @State private var projectQuery = ""
    @State private var sortNewest = true
    @State private var activeCaptureProject: UUID?
    @AppStorage("renovation.onboarded") private var onboarded = false
    @State private var guide = false
    @State private var guidePage = 0

    var body: some View {
        navigation { projects }
        .task(id:refreshToken) { await workspace.reload(location:store.location); guide = !onboarded }
        .onChange(of:store.records) { _,_ in refresh() }
        .onChange(of:store.houseRecords) { _,_ in refresh() }
        .onChange(of:scenePhase) { _,phase in if phase == .active { refresh() } }
        .onChange(of:store.location.documentsURL) { _,_ in refresh() }
        .sheet(isPresented:$settings,onDismiss:refresh) { SettingsView(includesProfile:true).environment(store) }
        .sheet(isPresented:$guide) { onboarding }
        .sheet(isPresented:$scan,onDismiss:{ if let requestedScan { self.requestedScan = nil; scanMode = requestedScan } }) { scanChoices.presentationDetents([.medium,.large]) }
        .fullScreenCover(item:$scanMode,onDismiss:refresh) { mode in
            ProjectCaptureView(mode:mode,projectID:activeCaptureProject,store:store,workspace:workspace,onSaved:attach)
        }
        .alert("New project",isPresented:$creating) {
            TextField("Project name",text:$projectName)
            Button("Create") { workspace.create(projectName); projectName = "" }
            Button("Cancel",role:.cancel) {}
        } message: { Text("A place, such as a flat or building address.") }
        .alert("Project library",isPresented:Binding(get:{ workspace.error != nil },set:{ if !$0 { workspace.error = nil } })) {
            Button("OK") { workspace.error = nil }
        } message: { Text(workspace.error ?? "") }
        .environment(workspace)
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
                .navigationDestination(for:UUID.self) { id in ProjectChatWorkspace(projectID:id,onScan:beginScan,onCapture:{ mode in beginCapture(mode,projectID:id) }) }
                .navigationDestination(for:ProjectReference.self) { reference in
                    if let entry = workspace.destination(reference) { RenovationItemDestination(entry:entry) }
                    else { ContentUnavailableView("Item unavailable",systemImage:"icloud.slash",description:Text("Reconnect its library to open this item. Your project reference has been kept.")) }
                }
        }
    }
    private func beginCapture(_ mode:ScanMode,projectID:UUID) {
        activeCaptureProject = projectID; workspace.currentProjectID = projectID
        Task {
            if let prefs = workspace.project(projectID)?.details?.preferences {
                if let value = prefs.language,!value.isEmpty { UserDefaults.standard.set(value,forKey:AppLanguage.preferenceKey) }
                if let value = prefs.units,MeasurementUnit(rawValue:value) != nil { UserDefaults.standard.set(value,forKey:"measurementUnit") }
                if let value = prefs.exportFormat { UserDefaults.standard.set(value,forKey:"export.defaultFormat") }
                if let value = prefs.photos { UserDefaults.standard.set(value,forKey:ScanPhotoPolicy.preferenceKey) }
                if prefs.storage == "local",store.isCloud { store.switchLocation(to:.local()) }
                if prefs.storage == "icloud",!store.isCloud {
                    await store.setCloudEnabled(true)
                    guard store.isCloud else { workspace.error = AppLanguage.text("Connect iCloud in App settings before scanning into it."); return }
                }
            }
            scanMode = mode
        }
    }
    private func beginScan() { activeCaptureProject = workspace.currentProjectID; scan = true }
    private var projects: some View {
        ScrollView {
            VStack(spacing:16) { UnfinishedScansView()
            if workspace.index.projects.isEmpty { ContentUnavailableView { Label("Your projects",systemImage:"folder") } description: { Text("Keep scans, designs and survey notes together.") } actions: { Button("Create a project") { creating = true } } }
            LazyVGrid(columns:sizeClass == .compact ? [GridItem(.flexible()),GridItem(.flexible())] : [GridItem(.adaptive(minimum:200))],spacing:14) {
            ForEach(workspace.index.projects.filter { projectQuery.isEmpty || ($0.isUnsorted ? AppLanguage.text("Unsorted") : $0.name).localizedCaseInsensitiveContains(projectQuery) }.sorted { sortNewest ? $0.modifiedAt > $1.modifiedAt : $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { project in
                NavigationLink(value:project.id) { ProjectSummary(project:project,workspace:workspace,card:true) }.buttonStyle(.plain)
            }
            } }.frame(maxWidth:.infinity).padding()
        }.navigationTitle("Projects").searchable(text:$projectQuery,prompt:"Search projects")
            .toolbar { ToolbarItemGroup(placement:.topBarLeading) {
                Button("New project",systemImage:"plus") { creating = true }.labelStyle(.iconOnly)
                Menu("Sort",systemImage:"arrow.up.arrow.down") { Toggle("Newest first",isOn:$sortNewest) }
            } }
            .refreshable { await workspace.reload(location:store.location) }
    }
    private var scanChoices: some View {
        NavigationStack {
            List {
                Section("Save to project") {
                    Picker("Project",selection: Binding(get: { workspace.currentProject?.isUnsorted == true ? nil : workspace.currentProjectID },set: { workspace.currentProjectID = $0 })) {
                        Text("Unsorted").tag(UUID?.none)
                        ForEach(workspace.index.projects.filter { !$0.isUnsorted }) { project in Text(project.name).tag(Optional(project.id)) }
                    }.pickerStyle(.menu)
                }
                Section("Scan") {
                    scanChoice(.house,"Scan a house","house")
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
        Button { activeCaptureProject = workspace.currentProjectID; requestedScan = mode; scan = false } label: { Label(name,systemImage:icon) }.disabled(!ScanCoordinator.isSupported)
    }
    private var onboarding: some View {
        NavigationStack {
            VStack(spacing:24) {
                Image(systemName:["folder","viewfinder","ruler"][guidePage]).font(.system(size:64)).accessibilityHidden(true)
                Text(LocalizedStringKey(["Create a project","Scan your space","Review and verify"][guidePage])).font(.title).multilineTextAlignment(.center)
                Text(LocalizedStringKey(["Group a building's scans, designs, photos and notes in one place.","Choose House or Technik room. Your original scan stays separate from design edits.","Check important dimensions before sharing a report. Capture-derived data is device validation pending."][guidePage])).multilineTextAlignment(.center)
                Button(guidePage == 2 ? "Get started" : "Next") { if guidePage < 2 { guidePage += 1 } else { onboarded = true; guide = false } }.buttonStyle(.borderedProminent)
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
    let store: RoomStore
    let workspace: RenovationWorkspace
    let onSaved: (ProjectReference.Kind,UUID,String) -> Void
    var body: some View {
        Group {
            if mode == .technicalRoom {
                TechnicalRoomScanView(voiceProjectID:projectID,workspace:workspace,onSaved:{ onSaved(.technicalRoom,$0,"local") })
            } else {
                ScanView(mode:mode,voiceProjectID:projectID,workspace:workspace,onSaved:{ onSaved(mode == .house ? .house : .room,$0.id,store.isCloud ? "icloud" : "local") })
            }
        }
        .environment(store)
        .environment(workspace)
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
                    .padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.secondary.opacity(0.08),in:RoundedRectangle(cornerRadius:22))
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
    let url: URL?
    var size:CGFloat = 72
    @State private var image: CGImage?
    var body: some View {
        Group {
            if let image { Image(decorative:image,scale:1).resizable().scaledToFit() }
            else { Image(systemName:"square.split.bottomrightquarter").font(.title2).foregroundStyle(.secondary) }
        }.frame(maxWidth:size).frame(height:size).background(.quaternary,in:RoundedRectangle(cornerRadius:8))
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
    var card = false
    @Environment(RenovationWorkspace.self) private var workspace
    @State private var renaming = false
    @State private var name = ""
    var body: some View {
        NavigationLink(value:openAsDesign ? designReference : entry.reference) {
            if card {
                VStack(alignment:.leading,spacing:8) {
                    ProjectCover(url:coverURL,size:140).frame(maxWidth:.infinity)
                    Text(workspace.title(entry)).font(.headline).lineLimit(2)
                    Text(String(entry.roomCount)+" "+AppLanguage.text("Rooms")).font(.caption).foregroundStyle(.secondary)
                    if let area = entry.area { Text(MeasurementFormat.squareMeters(area)).font(.caption).foregroundStyle(.secondary) }
                    Text(entry.date,style:.date).font(.caption2).foregroundStyle(.tertiary)
                }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.secondary.opacity(0.08),in:RoundedRectangle(cornerRadius:22))
            } else {
            HStack {
                Image(systemName:entry.isDesign ? "square.stack.3d.up" : entry.reference.kind == .technicalRoom ? "wrench.and.screwdriver" : "house")
                VStack(alignment:.leading) { Text(workspace.title(entry)); Text(entry.date,style:.date).font(.caption).foregroundStyle(.secondary) }
            }
            }
        }
        .contextMenu {
            Button("Rename") { name = workspace.title(entry); renaming = true }
            Button("Duplicate") { Task { await workspace.duplicate(entry) } }
            NavigationLink("Open in Studio",value:designReference)
            Menu("Move to project") { ForEach(workspace.index.projects) { project in Button(project.isUnsorted ? AppLanguage.text("Unsorted") : project.name) { workspace.assign(entry.reference,to:project.id) } } }
            ShareLink(item:entry.url) { Label("Share",systemImage:"square.and.arrow.up") }
        }
        .alert("Rename",isPresented:$renaming) {
            TextField("Name",text:$name)
            Button("Save") { workspace.rename(entry,to:name) }
            Button("Cancel",role:.cancel) {}
        } message: { Text("This name is stored in the project index. The original scan stays unchanged.") }
    }
    private var coverURL:URL {
        if !entry.isDesign { return entry.url.appendingPathComponent("thumbnail.png") }
        let location = StorageLocation(kind:.local,documentsURL:entry.root)
        let source = entry.reference.kind == .designHouse ? location.housePackageURL(for:entry.reference.itemID) : entry.reference.kind == .designRoom ? location.packageURL(for:entry.reference.itemID) : entry.root.appendingPathComponent("TechnicalRooms/\(entry.reference.itemID.uuidString).technicalroom")
        return source.appendingPathComponent("thumbnail.png")
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
                Section("Studio designs") { ForEach(project.references.compactMap(workspace.entry).filter(\.isDesign)) { ProjectEntryRow(entry:$0) } }
                Section("Exports") { NavigationLink("Project report and exports") { ProjectDeliverablesView(projectID:projectID) } }
                Section("Measurements") {
                    NavigationLink("Quantities") { ProjectQuantitiesView(projectID:projectID) }
                    NavigationLink("Verify with a known distance") { ProjectVerificationView(projectID:projectID) }
                }
                Section("Photos & notes") {
                    NavigationLink("Photos") { ProjectPhotosView(projectID:projectID) }
                    NavigationLink("Notes & task pins") { ProjectPinsView(projectID:projectID) }
                    NavigationLink("Voice notes") { ProjectVoiceNotesView(projectID:projectID) }
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


#if os(iOS)
/// A project owns its three working areas; switching tabs never changes project.
struct ProjectChatWorkspace: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var profile = false
    @Environment(RoomStore.self) private var store
    let projectID: UUID
    var onScan: () -> Void
    var onCapture: (ScanMode) -> Void
    @Environment(RenovationWorkspace.self) private var workspace
    private var entries: [ProjectLibraryEntry] {
        workspace.project(projectID)?.references.compactMap(workspace.entry) ?? []
    }
    var body: some View {
        TabView {
            ProjectDetailsEditor(projectID:projectID).tabItem { Label("Project",systemImage:"building.2") }
            scanCards(entries.filter { $0.reference.kind == .house || $0.reference.kind == .room },mode:.house).tabItem { Label("House",systemImage:"house") }
            scanCards(entries.filter { $0.reference.kind == .technicalRoom },mode:.technicalRoom).tabItem { Label("Technik",systemImage:"wrench.and.screwdriver") }
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    Text("Saved Studio designs").font(.headline); cards(entries.filter(\.isDesign),studio:false)
                    Text("Create from a scan").font(.headline); cards(entries.filter { !$0.isDesign },studio:true)
                }.padding()
            }.tabItem { Label("Studio",systemImage:"cube.transparent") }
            ProjectDetailsEditor(projectID:projectID,settings:true).tabItem { Label("Settings",systemImage:"gearshape") }
        }
        .navigationTitle(workspace.project(projectID).map { $0.isUnsorted ? "Unsorted" : $0.name } ?? "Project")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { workspace.currentProjectID = projectID }
        .sheet(isPresented:$profile) { SettingsView(includesProfile:true).environment(store) }
        .toolbar { ToolbarItem(placement:.topBarTrailing) {
            Button { profile = true } label: { Image(systemName:"person.crop.circle") }.accessibilityLabel("Profile and settings")
        } }
        .toolbar { ToolbarItem(placement:.topBarTrailing) {
            NavigationLink { RenovationProjectPage(projectID:projectID,onScan:startScan) } label: { Image(systemName:"ellipsis.circle") }.accessibilityLabel("Project details, notes and exports")
        } }
    }
    private func cards(_ values:[ProjectLibraryEntry],studio:Bool = false) -> some View {
        LazyVGrid(columns:sizeClass == .compact ? [GridItem(.flexible()),GridItem(.flexible())] : [GridItem(.adaptive(minimum:180))],spacing:14) {
            ForEach(values) { ProjectEntryRow(entry:$0,openAsDesign:studio,card:true).buttonStyle(.plain) }
        }
    }
    private func scanCards(_ values:[ProjectLibraryEntry],mode:ScanMode) -> some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Button(mode == .house ? "Scan a house" : "Scan Technik room",systemImage:"viewfinder") { onCapture(mode) }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                cards(values)
                if values.isEmpty { ContentUnavailableView("No scans yet",systemImage:mode == .house ? "house" : "cube") }
            }.padding()
        }
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

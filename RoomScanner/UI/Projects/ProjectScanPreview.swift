import SwiftUI

struct ProjectScanPreview: View {
    let entries: [ProjectLibraryEntry]
    enum Mode: String, CaseIterable { case plan = "Floor plan", model = "3D", measure = "Measure", photos = "Photos" }
    @State private var reference: ProjectReference?
    @State private var mode = Mode.plan
    @State private var house: House?
    @State private var technical: TechnicalRoomPackage?
    @State private var story: Int?
    @State private var photos: [SurveyPhotoImage] = []
    @State private var photo: SurveyPhotoImage?
    @State private var error: String?
    @State private var viewer = ViewerState()
    private var scans: [ProjectLibraryEntry] { entries.filter { !$0.isDesign } }
    private var entry: ProjectLibraryEntry? { scans.first { $0.reference == reference } }
    private var shown: House? { house.map { value in House(id:value.id,name:value.name,stories:value.stories.filter { story == nil || $0.index == story }) } }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Picker("Scan",selection:$reference) { ForEach(scans) { Text($0.title).tag(Optional($0.reference)) } }
            Picker("View",selection:$mode) { ForEach(Mode.allCases,id:\.self) { Text(AppLanguage.text($0.rawValue)).tag($0) } }.pickerStyle(.segmented)
            if let house,house.stories.count > 1 {
                Picker("Level",selection:$story) { ForEach(house.stories,id:\.index) { Text(StoryNaming.localizedName(for:$0.index)).tag(Optional($0.index)) } }
            }
            if let error { Text(error).foregroundStyle(DS.ColorToken.error.color) }
            switch mode {
            case .plan:
                if let shown { Plan2DView(house:shown).frame(height:320) }
                else if technical != nil { Text("A dimensioned room-shell floor plan is not stored in this utility-room capture. Use its 3D survey.") }
            case .model:
                if let shown { ViewerView(house:shown,state:viewer,photoPackageURL:entry?.url).frame(height:320) }
                else if let technical { TechnicalSavedScanView(package:technical).frame(height:360) }
            case .measure:
                if let shown { ForEach(shown.allRooms) { room in
                    let q = RenovationQuantities(room)
                    DisclosureGroup(room.name) { ForEach(ProjectQuantitiesCSV.lines(q,locale:AppLanguage.locale),id:\.self) { Text($0).font(.caption) } }
                } }
                else if let technical {
                    LabeledContent("Equipment",value:String(technical.document.room.equipment.count))
                    LabeledContent("Pipe runs",value:String(technical.document.room.pipeRuns.count))
                }
            case .photos:
                if photos.isEmpty { Text("No photos in this scan") }
                ScrollView(.horizontal) {
                    HStack { ForEach(photos) { image in
                        Button { photo = image } label: {
                            VStack { SurveyPhotoCanvas(data:image.jpegData).frame(width:180,height:150); Text(image.title).font(.caption).lineLimit(2) }
                        }.buttonStyle(.plain)
                    } }
                }
            }
            if let entry {
                NavigationLink("Open in Design",value:ProjectReference(kind:entry.reference.kind == .house ? .designHouse : entry.reference.kind == .room ? .designRoom : .designTechnical,itemID:entry.reference.itemID,library:entry.reference.library))
            }
        }
        .task { reference = scans.first?.reference }
        .task(id:reference) { await load() }
        .sheet(item:$photo) { selected in SurveyPhotoGallery(photos:photos,initial:selected.id) }
    }
    private func load() async {
        house = nil; technical = nil; photos = []; error = nil
        guard let entry else { return }
        do {
            let result = try await Task.detached { () throws -> (House?,TechnicalRoomPackage?,[SurveyPhotoImage]) in
                if entry.reference.kind == .technicalRoom {
                    let package = try TechnicalRoomPackage.read(from:entry.url)
                    return (nil,package,SurveyPhotoStore.images(technical:package))
                }
                let house: House
                if entry.reference.kind == .house { house = try HousePackage.readHouse(from:entry.url) }
                else { house = House(room:try RoomPackage.readPlan(from:entry.url)) }
                return (house,nil,try SurveyPhotoStore.images(from:entry.url,house:house))
            }.value
            guard reference == entry.reference else { return }
            house = result.0; technical = result.1; photos = result.2; story = result.0?.stories.first?.index
        } catch { self.error = error.localizedDescription }
    }
}

struct ProjectPhotosView: View {
    let projectID: UUID
    @Environment(RenovationWorkspace.self) private var workspace
    @State private var photos: [SurveyPhotoImage] = []
    @State private var selected: SurveyPhotoImage?
    @State private var warning: String?
    var body: some View {
        List {
            ForEach(photos) { image in
                Button { selected = image } label: {
                    HStack { Image(systemName:"camera"); Text(image.title) }
                }
            }
            if photos.isEmpty { Text("No project photos yet") }
            if let warning { Text(warning).font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("Photos").task {
            let entries = workspace.project(projectID)?.references.compactMap(workspace.entry).filter { !$0.isDesign } ?? []
            let result = await Task.detached { () -> ([SurveyPhotoImage],[String]) in
                var images: [SurveyPhotoImage] = [], warnings: [String] = [], ids = Set<UUID>(), bytes = 0
                for entry in entries {
                    do {
                        let loaded: [SurveyPhotoImage]
                        if entry.reference.kind == .technicalRoom { loaded = SurveyPhotoStore.images(technical:try TechnicalRoomPackage.read(from:entry.url)) }
                        else {
                            let house: House
                            if entry.reference.kind == .house { house = try HousePackage.readHouse(from:entry.url) }
                            else { house = House(room:try RoomPackage.readPlan(from:entry.url)) }
                            loaded = try SurveyPhotoStore.images(from:entry.url,house:house)
                        }
                        for image in loaded where !ids.contains(image.id) {
                            if images.count >= 200 || bytes+image.jpegData.count > 64*1_048_576 { warnings.append(AppLanguage.text("Photo display budget reached. Open individual scans to see remaining photos.")); break }
                            images.append(image); ids.insert(image.id); bytes += image.jpegData.count
                        }
                    } catch { warnings.append(entry.title+": "+error.localizedDescription) }
                }
                return (images,warnings)
            }.value
            photos = result.0; warning = result.1.isEmpty ? nil : result.1.joined(separator:"\n")
        }.sheet(item:$selected) { image in SurveyPhotoGallery(photos:photos,initial:image.id) }
    }
}

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

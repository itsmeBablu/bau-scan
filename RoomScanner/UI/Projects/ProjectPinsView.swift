import SwiftUI

struct ProjectPinsView: View {
    let projectID: UUID
    @Environment(RenovationWorkspace.self) private var workspace
    @State private var selected: ProjectReference?
    @State private var house: House?
    @State private var story = 0
    @State private var draft: ProjectPin?
    @State private var photos: [SurveyPhotoImage] = []
    @State private var design: SceneEditDocument?
    @State private var error: String?
    private var sources: [ProjectLibraryEntry] { workspace.project(projectID)?.references.compactMap(workspace.entry).filter { $0.reference.kind == .house || $0.reference.kind == .room } ?? [] }
    private var pins: [ProjectPin] { (workspace.index.pins ?? []).filter { $0.projectID == projectID && $0.reference == selected && $0.story == story } }
    private var shown: House? { house.map { House(id:$0.id,name:$0.name,stories:$0.stories.filter { $0.index == story }) } }
    var body: some View {
        VStack {
            Picker("Scan",selection:$selected) { ForEach(sources) { Text($0.title).tag(Optional($0.reference)) } }.padding(.horizontal)
            if let house {
                Picker("Level",selection:$story) { ForEach(house.stories,id:\.index) { Text(StoryNaming.localizedName(for:$0.index)).tag($0.index) } }.padding(.horizontal)
            }
            if let shown {
                GeometryReader { geometry in
                    let bounds = shown.bounds
                    let scale = min(Double(max(1,geometry.size.width-32))/max(0.1,bounds.width),Double(max(1,geometry.size.height-32))/max(0.1,bounds.height))
                    let ox = (Double(geometry.size.width)-bounds.width*scale)/2, oy = (Double(geometry.size.height)-bounds.height*scale)/2
                    ZStack(alignment:.topLeading) {
                        Canvas { context,_ in
                            for room in shown.allRooms {
                                for wall in room.walls {
                                    let a = room.transform.apply(wall.start), b = room.transform.apply(wall.end)
                                    var path = Path(); path.move(to:CGPoint(x:ox+(a.x-bounds.minX)*scale,y:oy+(bounds.maxY-a.y)*scale))
                                    path.addLine(to:CGPoint(x:ox+(b.x-bounds.minX)*scale,y:oy+(bounds.maxY-b.y)*scale))
                                    context.stroke(path,with:.color(.primary),lineWidth:3)
                                }
                            }
                        }.contentShape(Rectangle()).onTapGesture { location in
                            guard let selected else { return }
                            let p = Point2D(x:bounds.minX+(Double(location.x)-ox)/scale,y:bounds.maxY-(Double(location.y)-oy)/scale)
                            draft = .init(projectID:projectID,reference:selected,story:story,position:p)
                        }.accessibilityLabel("Floor plan. Tap to add a task pin.")
                        ForEach(pins) { pin in
                            Button { draft = pin } label: { Image(systemName:pin.status == .resolved ? "checkmark.circle.fill" : "mappin.circle.fill").font(.title2) }
                                .position(x:ox+(pin.position.x-bounds.minX)*scale,y:oy+(bounds.maxY-pin.position.y)*scale)
                                .accessibilityLabel(pin.text.isEmpty ? AppLanguage.text("Task pin") : pin.text)
                        }
                    }
                }.frame(minHeight:220)
                List {
                    Text("Tap the plan to add a note. Positions are annotations, not verified measurements.").font(.caption)
                    ForEach(pins) { pin in Button(pin.text.isEmpty ? AppLanguage.text("Task pin") : pin.text) { draft = pin } }
                    Button("Add task pin",systemImage:"mappin") {
                        if let selected { draft = .init(projectID:projectID,reference:selected,story:story,position:shown.bounds.center) }
                    }
                }.frame(maxHeight:200)
            } else { ContentUnavailableView("No floor plan available",systemImage:"square.dashed",description:Text("Add a room or whole-home scan to place renovation pins.")) }
            if let error { Text(error).foregroundStyle(DS.ColorToken.error.color).font(.caption) }
        }.navigationTitle("Notes & task pins")
            .task { if selected == nil { selected = sources.first?.reference } }
            .task(id:selected) { await load() }
            .sheet(item:$draft) { pin in
                ProjectPinEditor(pin:pin,photos:photos,elements:design?.engineeringElements.filter { $0.story == story && $0.kind != "Floor" } ?? [],phase:nil) { edited,phase in save(edited,phase:phase) } onDelete: { id in
                    workspace.change { $0.pins?.removeAll { $0.id == id } }; draft = nil
                }
            }
    }
    private func load() async {
        house = nil; design = nil; photos = []
        guard let selected,let entry = workspace.entry(selected) else { return }
        do {
            let value = try await Task.detached {
                let house: House
                let source: SceneEditDocument.Source
                if selected.kind == .house { house = try HousePackage.readHouse(from:entry.url); source = .house }
                else { house = House(room:try RoomPackage.readPlan(from:entry.url)); source = .room }
                let saved = try SceneEditStore.read(SceneEditStore.url(root:entry.root,source:source,id:selected.itemID),source:source,id:selected.itemID)
                return (house,try SurveyPhotoStore.images(from:entry.url,house:house),saved ?? SceneEditDocument.seed(house:house,source:source,id:selected.itemID))
            }.value
            guard self.selected == selected else { return }
            house = value.0; photos = value.1; design = value.2; story = value.0.stories.first?.index ?? 0
        } catch { self.error = error.localizedDescription }
    }
    private func save(_ pin: ProjectPin,phase: StudioEngineering.Phase?) {
        do {
            if let phase,let id = pin.elementID,var doc = design,let entry = workspace.entry(pin.reference) {
                var data = doc.engineering ?? .init(); var record = data.record(id)
                record.phase = phase; data.set(record); doc.engineering = data
                design = try SceneEditStore.write(doc,to:SceneEditStore.url(root:entry.root,source:doc.source,id:doc.sourceID))
            }
            workspace.change { if $0.pins == nil { $0.pins = [] }; $0.pins?.removeAll { $0.id == pin.id }; $0.pins?.append(pin) }
            draft = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct ProjectPinEditor: View {
    @State var pin: ProjectPin
    let photos: [SurveyPhotoImage]
    let elements: [SceneEditDocument.EngineeringElement]
    @State var phase: StudioEngineering.Phase?
    var onSave: (ProjectPin,StudioEngineering.Phase?) -> Void
    var onDelete: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                TextField("Task or note",text:$pin.text,axis:.vertical)
                Picker("Status",selection:$pin.status) { ForEach(ProjectPin.Status.allCases,id:\.self) { Text(AppLanguage.text($0.rawValue)).tag($0) } }
                Picker("Photo",selection:$pin.photoID) {
                    Text("None").tag(nil as UUID?)
                    ForEach(photos) { Text($0.title).tag(Optional($0.id)) }
                }
                Picker("Element",selection:$pin.elementID) {
                    Text("None").tag(nil as UUID?)
                    ForEach(elements) { Text($0.name).tag(Optional($0.id)) }
                }
                if pin.elementID != nil {
                    Picker("Renovation tag",selection:$phase) {
                        Text("Keep existing tag").tag(nil as StudioEngineering.Phase?)
                        ForEach(StudioEngineering.Phase.allCases,id:\.self) { Text(AppLanguage.text($0.rawValue)).tag(Optional($0)) }
                    }
                    Text("The tag is stored in the existing Design phase data. The original capture is unchanged.").font(.caption)
                }
                Button("Delete pin",role:.destructive) { onDelete(pin.id); dismiss() }
            }.onChange(of:pin.elementID) { _,_ in phase = nil }.navigationTitle("Task pin")
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement:.confirmationAction) { Button("Save") { onSave(pin,phase); dismiss() }.disabled(pin.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
                }
        }.presentationDetents([.medium,.large])
    }
}

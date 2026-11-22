import SwiftUI

/// Engineering annotations belong to the editable project, never to raw capture evidence.
struct StudioEngineering: Codable, Equatable {
    enum Phase: String, Codable, CaseIterable { case existing, remove, replace, new }
    enum ViewMode: String, Codable, CaseIterable { case all, existing, demolition, proposed }
    enum IssueStatus: String, Codable, CaseIterable {
        case open, inProgress, resolved
        var title: String { self == .inProgress ? "In progress" : rawValue.capitalized }
    }
    struct Verification: Codable, Equatable {
        var dimensions: TechnicalPoint3
        var reference: String
        var date: Date
    }
    struct Record: Codable, Equatable, Identifiable {
        var id: UUID // persistent element ID
        var phase = Phase.existing
        var note = ""
        var verification: Verification?
        var thicknessOverride: Double? = nil
        var thicknessReference: String? = nil
        var issue = ""
        var assignee = ""
        var issueStatus = IssueStatus.open
    }
    var view = ViewMode.all
    var records: [Record] = [] { didSet { rebuildIndex() } }
    private var recordIndex: [UUID:Int] = [:]
    private enum CodingKeys: String,CodingKey { case view,records }
    init(view: ViewMode = .all,records: [Record] = []) {
        self.view = view; self.records = records; rebuildIndex()
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        view = try values.decode(ViewMode.self,forKey: .view)
        records = try values.decode([Record].self,forKey: .records)
        rebuildIndex()
    }
    private mutating func rebuildIndex() {
        recordIndex = [:]
        for (index,record) in records.enumerated() { recordIndex[record.id] = index }
    }
    func record(_ id: UUID) -> Record {
        guard let index = recordIndex[id],records.indices.contains(index),records[index].id == id else { return Record(id: id) }
        return records[index]
    }
    mutating func set(_ record: Record) {
        records.removeAll { $0.id == record.id }; records.append(record)
    }
    func includes(_ id: UUID) -> Bool {
        if view == .all { return true }
        let phase = record(id).phase
        switch view {
        case .all: return true
        case .existing: return phase != .new
        case .demolition: return phase == .remove || phase == .replace
        case .proposed: return phase != .remove
        }
    }
    func validate(ids: Set<UUID>,thicknessIDs: Set<UUID>,floorIDs: Set<UUID>) throws {
        guard records.count <= 20_000, Set(records.map(\.id)).count == records.count else { throw SceneEditDocument.Failure.invalid }
        for record in records {
            guard ids.contains(record.id), record.note.count <= 4000, record.issue.count <= 2000, record.assignee.count <= 240,(record.thicknessReference?.count ?? 0) <= 1000,
                  !floorIDs.contains(record.id) || record.phase == .existing else { throw SceneEditDocument.Failure.invalid }
            if let thickness = record.thicknessOverride {
                guard thicknessIDs.contains(record.id),thickness.isFinite,(0.005...2).contains(thickness),
                      let reference = record.thicknessReference,!reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,reference.count <= 1000 else { throw SceneEditDocument.Failure.invalid }
            }
            if let v = record.verification {
                guard !v.reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, v.reference.count <= 1000,
                      v.date.timeIntervalSince1970.isFinite,
                      [v.dimensions.x,v.dimensions.y,v.dimensions.z].allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 1000 }) else { throw SceneEditDocument.Failure.invalid }
            }
        }
    }
}

extension SceneEditDocument {
    struct EngineeringElement: Identifiable {
        var id: UUID
        var name: String
        var kind: String
        var story: Int
        /// Object local XYZ; wall length/height/thickness; opening width/height/nominal depth.
        var dimensions: TechnicalPoint3
    }
    /// Independently entered construction dimensions affect only the design copy.
    var architecturalShell: House {
        var overrides: [UUID:Double] = [:]
        for record in engineering?.records ?? [] { if let thickness = record.thicknessOverride { overrides[record.id] = thickness } }
        guard !overrides.isEmpty else { return shell }
        var house = shell
        for si in house.stories.indices { for ri in house.stories[si].rooms.indices {
            let id = house.stories[si].rooms[ri].id
            if let thickness = overrides[id] { house.stories[si].rooms[ri].floorSlabThickness = thickness }
            for wi in house.stories[si].rooms[ri].walls.indices {
                let id = house.stories[si].rooms[ri].walls[wi].id
                if let thickness = overrides[id] { house.stories[si].rooms[ri].walls[wi].thickness = thickness }
            }
        } }
        return house
    }
    var engineeringElements: [EngineeringElement] {
        let candidates = architecturalShell.allRooms.flatMap { room -> [EngineeringElement] in
            let floors: [EngineeringElement] = room.floorPolygon.count >= 3 ? [EngineeringElement(id: room.id,name: room.name+" · Floor",kind: "Floor",story: room.story,dimensions: .init(x: room.floorBounds.width,y: room.displayFloorSlabThickness,z: room.floorBounds.height))] : []
            return floors+room.walls.map { EngineeringElement(id: $0.id,name: room.name+" · Wall "+$0.id.uuidString.prefix(6),kind: "Wall",story: room.story,dimensions: .init(x: $0.segment.length,y: $0.height,z: $0.thickness)) }
        } + objects.map { EngineeringElement(id: $0.id,name: $0.name,kind: $0.family.title,story: $0.story,dimensions: $0.size) }
        var seen = Set<UUID>()
        return candidates.filter { seen.insert($0.id).inserted }
    }
    func engineeringSearch(_ query: String,selection: UUID?,limit: Int = 200) -> [EngineeringElement] {
        let all = engineeringElements,term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var matches = Array(all.filter { term.isEmpty || $0.name.localizedCaseInsensitiveContains(term) || $0.kind.localizedCaseInsensitiveContains(term) }.prefix(max(0,limit)))
        if let selection,!matches.contains(where: { $0.id == selection }),let element = all.first(where: { $0.id == selection }) { matches.append(element) }
        return matches
    }
    func includesElement(_ id: UUID?) -> Bool { id.map { engineering?.includes($0) ?? true } ?? true }
    var presentationObjects: [SceneEditObject] {
        objects.filter { includesElement($0.id) }.map { item in
            guard engineering?.view == .existing || engineering?.view == .demolition,
                  let reference = item.scanReference else { return item }
            var result = item
            result.position = reference.position; result.size = reference.size; result.yaw = reference.yaw
            result.axis = reference.axis; result.crossAxis = reference.crossAxis
            if let family = reference.family { result.family = family }
            return result
        }
    }
    func measurementStatus(_ element: EngineeringElement) -> String {
        guard let v = engineering?.record(element.id).verification else { return "Unverified" }
        return v.dimensions == element.dimensions ? "User verified" : "Changed · recheck required"
    }
    /// Quoted RFC4180 rows; spreadsheet formula prefixes are neutralised in textual cells.
    func engineeringCSV() -> Data {
        func cell(_ text: String) -> String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let safe = trimmed.first.map { "=+-@".contains($0) } == true ? "'"+text : text
            return "\""+safe.replacingOccurrences(of: "\"",with: "\"\"")+"\""
        }
        let header = ["Element ID","Name","Kind","Floor","Phase","X / width / wall length (m)","Y / height / floor slab (m)","Z / depth / wall thickness (m)","Measurement status","Verification reference","Verified at","Issue","Issue status","Assignee","Notes","Thickness source","Thickness reference"]
        var rows = [header]
        for element in engineeringElements {
            let r = engineering?.record(element.id) ?? .init(id: element.id)
            rows.append([element.id.uuidString,element.name,element.kind,String(element.story),r.phase.rawValue,
                         String(element.dimensions.x),String(element.dimensions.y),String(element.dimensions.z),measurementStatus(element),
                         r.verification?.reference ?? "",r.verification.map { ISO8601DateFormatter().string(from: $0.date) } ?? "",
                         r.issue,r.issue.isEmpty ? "" : r.issueStatus.rawValue,r.assignee,r.note,
                         element.kind == "Wall" || element.kind == "Floor" ? (r.thicknessOverride == nil ? "Base value · not supplied by scan" : "Independently entered") : "",r.thicknessReference ?? ""])
        }
        return Data((rows.map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n")+"\r\n").utf8)
    }
}

struct StudioEngineeringView: View {
    let session: SceneEditSession
    @Environment(\.dismiss) private var dismiss
    @State private var selected: UUID?
    @State private var search = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Renovation view") {
                    Picker("Show",selection: Binding(get: { session.document.engineering?.view ?? .all },set: { mode in
                        change { $0.view = mode }
                    })) { ForEach(StudioEngineering.ViewMode.allCases,id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                    Text("Existing includes elements to be removed. Proposed excludes removed elements. Replace keeps the design element in the proposed view; its original scan remains preserved.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Element register") {
                    TextField("Find a wall or equipment",text: $search)
                    Picker("Element",selection: $selected) {
                        Text("Choose an element").tag(UUID?.none)
                        ForEach(session.document.engineeringSearch(search,selection: selected)) { element in
                            Text(element.name+" · Floor \(element.story)").tag(Optional(element.id))
                        }
                    }
                    if let element = session.document.engineeringElements.first(where: { $0.id == selected }) {
                        if let room = session.document.shell.allRooms.first(where: { $0.id == element.id }) {
                            Text(room.floorOutlineSource == .capturedSurface ? "Floor outline: captured surface" : room.floorOutlineSource == .wallBoundary ? "Floor outline: reconstructed from walls" : "Floor outline: estimated or legacy; verify the boundary").font(.caption).foregroundStyle(.secondary)
                        }
                        StudioEngineeringRecordView(element: element,record: session.document.engineering?.record(element.id) ?? .init(id: element.id),status: session.document.measurementStatus(element)) { record in
                            change { $0.set(record) }
                        }.id(element.id)
                    }
                }
                Section("Issues") {
                    let issues = session.document.engineering?.records.filter { !$0.issue.isEmpty } ?? []
                    if issues.isEmpty { Text("No issues recorded. Select an element to add one.").foregroundStyle(.secondary) }
                    ForEach(issues) { record in
                        Button { selected = record.id } label: {
                            VStack(alignment: .leading) {
                                Text(record.issue).lineLimit(2)
                                Text(record.issueStatus.title+" · "+record.assignee).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Engineering")
            .onAppear { selected = session.selectedID }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func change(_ action: (inout StudioEngineering) -> Void) {
        do { try session.change { document in
            var data = document.engineering ?? .init(); action(&data); document.engineering = data
        } } catch { self.error = error.localizedDescription }
    }
}

private struct StudioEngineeringRecordView: View {
    let element: SceneEditDocument.EngineeringElement
    let record: StudioEngineering.Record
    let status: String
    let commit: (StudioEngineering.Record) -> Void
    @State private var reference = ""
    var body: some View {
        if element.kind != "Floor" {
            Picker("Work",selection: binding(\.phase)) {
                ForEach(StudioEngineering.Phase.allCases,id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
        }
        Text("Dimensions (m): \(element.dimensions.x.formatted()) × \(element.dimensions.y.formatted()) × \(element.dimensions.z.formatted())")
        Text(status).font(.callout.weight(.medium))
        if element.kind == "Wall" || element.kind == "Floor" {
            StudioThicknessFields(element: element,record: record,commit: commit)
        }
        Text("Objects use local X/Y/Z; walls use length/height/thickness; floors use bounding width/slab thickness/bounding depth. Base wall and slab thickness are display assumptions. Verify all three dimensions independently before confirming.").font(.caption).foregroundStyle(.secondary)
        TextField("Measurement reference / instrument / surveyor",text: $reference)
        Button("Confirm current dimensions verified") {
            var next = record; next.verification = .init(dimensions: element.dimensions,reference: reference,date: Date()); commit(next)
        }.disabled(reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if let verification = record.verification {
            Text(verification.reference+" · "+verification.date.formatted()).font(.caption)
            Button("Clear verification",role: .destructive) { var next = record; next.verification = nil; commit(next) }
        }
        TextField("Survey notes",text: binding(\.note),axis: .vertical)
        TextField("Issue / required action",text: binding(\.issue),axis: .vertical)
        if !record.issue.isEmpty {
            Picker("Issue status",selection: binding(\.issueStatus)) {
                ForEach(StudioEngineering.IssueStatus.allCases,id: \.self) { Text($0.title).tag($0) }
            }
            TextField("Assignee",text: binding(\.assignee))
        }
    }
    private func binding<T>(_ path: WritableKeyPath<StudioEngineering.Record,T>) -> Binding<T> {
        Binding(get: { record[keyPath: path] },set: { value in var next = record; next[keyPath: path] = value; commit(next) })
    }
}

private struct StudioThicknessFields: View {
    let element: SceneEditDocument.EngineeringElement
    let record: StudioEngineering.Record
    let commit: (StudioEngineering.Record) -> Void
    @State private var thickness: Double
    @State private var reference: String
    init(element: SceneEditDocument.EngineeringElement,record: StudioEngineering.Record,commit: @escaping (StudioEngineering.Record) -> Void) {
        self.element = element; self.record = record; self.commit = commit
        _thickness = State(initialValue: record.thicknessOverride ?? (element.kind == "Wall" ? element.dimensions.z : element.dimensions.y))
        _reference = State(initialValue: record.thicknessReference ?? "")
    }
    var body: some View {
        Text(element.kind == "Wall" ? "Wall thickness" : "Floor slab thickness").font(.headline)
        Text(record.thicknessOverride == nil ? "Display assumption · not measured by RoomPlan" : "Entered construction dimension · "+(record.thicknessReference ?? "")).font(.caption).foregroundStyle(.secondary)
        TextField("Thickness (m)",value: $thickness,format: .number)
        TextField("Measurement or construction-document reference",text: $reference)
        Button("Apply entered thickness") {
            var next = record; next.thicknessOverride = thickness; next.thicknessReference = reference; commit(next)
        }.disabled(!thickness.isFinite || !(0.005...2).contains(thickness) || reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if record.thicknessOverride != nil {
            Button("Restore base display thickness") { var next = record; next.thicknessOverride = nil; next.thicknessReference = nil; commit(next) }
        }
        Text("Hidden construction cannot be determined from one scanned surface. Use a visible reveal, independent measurement or a referenced drawing.").font(.caption).foregroundStyle(.secondary)
    }
}

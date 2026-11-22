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
        var issue = ""
        var assignee = ""
        var issueStatus = IssueStatus.open
    }
    var view = ViewMode.all
    var records: [Record] = []
    func record(_ id: UUID) -> Record { records.first { $0.id == id } ?? Record(id: id) }
    mutating func set(_ record: Record) {
        records.removeAll { $0.id == record.id }; records.append(record)
    }
    func includes(_ id: UUID) -> Bool {
        let phase = record(id).phase
        switch view {
        case .all: return true
        case .existing: return phase != .new
        case .demolition: return phase == .remove || phase == .replace
        case .proposed: return phase != .remove
        }
    }
    func validate(ids: Set<UUID>) throws {
        guard records.count <= 20_000, Set(records.map(\.id)).count == records.count else { throw SceneEditDocument.Failure.invalid }
        for record in records {
            guard ids.contains(record.id), record.note.count <= 4000, record.issue.count <= 2000, record.assignee.count <= 240 else { throw SceneEditDocument.Failure.invalid }
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
    var engineeringElements: [EngineeringElement] {
        let candidates = shell.allRooms.flatMap { room in
            room.walls.map { EngineeringElement(id: $0.id,name: room.name+" · Wall "+$0.id.uuidString.prefix(6),kind: "Wall",story: room.story,dimensions: .init(x: $0.segment.length,y: $0.height,z: $0.thickness)) }
        } + objects.map { EngineeringElement(id: $0.id,name: $0.name,kind: $0.family.title,story: $0.story,dimensions: $0.size) }
        var seen = Set<UUID>()
        return candidates.filter { seen.insert($0.id).inserted }
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
        let header = ["Element ID","Name","Kind","Floor","Phase","Local X / wall length (m)","Local Y / wall height (m)","Local Z / wall thickness (m)","Measurement status","Verification reference","Verified at","Issue","Issue status","Assignee","Notes"]
        var rows = [header]
        for element in engineeringElements {
            let r = engineering?.record(element.id) ?? .init(id: element.id)
            rows.append([element.id.uuidString,element.name,element.kind,String(element.story),r.phase.rawValue,
                         String(element.dimensions.x),String(element.dimensions.y),String(element.dimensions.z),measurementStatus(element),
                         r.verification?.reference ?? "",r.verification.map { ISO8601DateFormatter().string(from: $0.date) } ?? "",
                         r.issue,r.issue.isEmpty ? "" : r.issueStatus.rawValue,r.assignee,r.note])
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
                        ForEach(session.document.engineeringElements.filter { $0.id == selected || search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.kind.localizedCaseInsensitiveContains(search) }.prefix(200)) { element in
                            Text(element.name+" · Floor \(element.story)").tag(Optional(element.id))
                        }
                    }
                    if let element = session.document.engineeringElements.first(where: { $0.id == selected }) {
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
        Picker("Work",selection: binding(\.phase)) {
            ForEach(StudioEngineering.Phase.allCases,id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
        Text("Dimensions (m): \(element.dimensions.x.formatted()) × \(element.dimensions.y.formatted()) × \(element.dimensions.z.formatted())")
        Text(status).font(.callout.weight(.medium))
        Text("Object dimensions use local X/Y/Z. Walls use length/height/thickness. Confirm all three against independent measurements before marking verified.").font(.caption).foregroundStyle(.secondary)
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

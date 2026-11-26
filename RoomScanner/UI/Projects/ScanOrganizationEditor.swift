import SwiftUI

/// Shared catalogue fields. No scanner, AR session or package writer belongs here.
struct ScanOrganizationFields: View {
    @Binding var value: ScanOrganization
    @Environment(\.locale) private var locale
    private var levelSelection: Binding<Int> {
        Binding(get: { value.level ?? (value.otherLevelName == nil ? -1002 : -1001) }, set: { selection in
            value.level = selection >= -100 ? selection : nil
            value.otherLevelName = selection == -1001 ? (value.otherLevelName ?? "") : nil
        })
    }
    var body: some View {
        Section("Location") {
            Picker("Level", selection: levelSelection) {
                Text("Unassigned level").tag(-1002)
                ForEach(ScanOrganization.offeredLevels, id: \.self) { level in
                    Text(StoryNaming.localizedName(for: level, locale: locale)).tag(level)
                }
                if let level = value.level, !ScanOrganization.offeredLevels.contains(level) {
                    Text(StoryNaming.localizedName(for: level, locale: locale)).tag(level)
                }
                Text("Other level").tag(-1001)
            }
            if value.otherLevelName != nil { TextField("Level name", text: text(\.otherLevelName, retainEmpty: true)) }
            TextField("Building (optional)", text: text(\.buildingName))
            TextField("Room or zone (optional)", text: text(\.zoneName))
            TextField("Number (optional)", value: $value.number, format: .number.grouping(.never))
        }
        Section("Name preview") { Text(value.displayName(locale: locale)) }
    }
    private func text(_ keyPath: WritableKeyPath<ScanOrganization, String?>, retainEmpty: Bool = false) -> Binding<String> {
        Binding(get: { value[keyPath: keyPath] ?? "" }, set: { text in
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            value[keyPath: keyPath] = clean.isEmpty && !retainEmpty ? nil : text
        })
    }
}

struct ScanOrganizationEditor: View {
    let entry: ProjectLibraryEntry
    private let expected: ScanOrganization?
    @State private var value: ScanOrganization
    @State private var detectedStories: [Int] = []
    @State private var message: String?
    @State private var confirmingCollision = false
    @Environment(RenovationWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    init(entry: ProjectLibraryEntry, organization: ScanOrganization?) {
        self.entry = entry; expected = organization
        _value = State(initialValue: organization ?? .init(kind: entry.reference.kind))
    }
    private var projectID: UUID? { workspace.index.projects.first { $0.references.contains(entry.reference) }?.id }
    private var collisions: [ProjectReference] {
        projectID.map { workspace.index.numberCollisions(for: value, projectID: $0, excluding: entry.reference) } ?? []
    }
    private var nextNumber: Int? {
        projectID.flatMap { workspace.index.suggestedNumber(for: value, projectID: $0, excluding: entry.reference) }
    }
    var body: some View {
        NavigationStack {
            Form {
                ScanOrganizationFields(value: $value)
                Section {
                    if let nextNumber { Button("Suggest next number") { value.number = nextNumber } }
                    Text("Only project labels change. Scan geometry and detected stories stay unchanged.").font(.caption).foregroundStyle(.secondary)
                }
                if detectedStories.count > 1 {
                    Section("Map detected stories") {
                        ForEach(detectedStories, id: \.self) { index in
                            Picker(StoryNaming.localizedName(for: index, locale: locale), selection: storyLevel(index)) {
                                Text("Unassigned level").tag(Int?.none)
                                ForEach(ScanOrganization.offeredLevels, id: \.self) { level in
                                    Text(StoryNaming.localizedName(for: level, locale: locale)).tag(Optional(level))
                                }
                                if let level = value.storyLevels?[index], !ScanOrganization.offeredLevels.contains(level) {
                                    Text(StoryNaming.localizedName(for: level, locale: locale)).tag(Optional(level))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Scan organization")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if collisions.isEmpty { save() } else { confirmingCollision = true } }
                        .disabled((try? value.validate()) == nil)
                }
            }
            .task(id: entry.reference.id) {
                guard entry.reference.kind == .house else { return }
                do {
                    let url = entry.url
                    detectedStories = try await Task.detached(priority: .utility) {
                        try HousePackage.readHouse(from: url).stories.map(\.index).sorted()
                    }.value
                } catch { message = error.localizedDescription }
            }
            .confirmationDialog("This number is already used here", isPresented: $confirmingCollision, titleVisibility: .visible) {
                if let nextNumber { Button("Use next available number") { value.number = nextNumber; save() } }
                Button("Keep both") { save() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Existing scans are kept. Choose another number or keep both labels.") }
            .alert("Scan organization", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
        }
    }
    private func storyLevel(_ index: Int) -> Binding<Int?> {
        Binding(get: { value.storyLevels?[index] }, set: { level in
            if value.storyLevels == nil { value.storyLevels = [:] }
            value.storyLevels?[index] = level
        })
    }
    private func save() {
        if workspace.organize(value, reference: entry.reference, expected: expected) { dismiss() }
        else { message = workspace.error }
    }
}

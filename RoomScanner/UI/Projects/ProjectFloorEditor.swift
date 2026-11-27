import SwiftUI

/// Building floor labels live in project metadata. Scan story indices and all
/// photo/voice UUID associations remain untouched.
struct ProjectFloorEditor:View {
    let projectID:UUID
    @Environment(RenovationWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var details = ProjectDetails()
    @State private var baseline:ProjectDetails?
    @State private var loaded = false
    @State private var message:String?
    @State private var newLevel = 0
    private var levels:[Int] {
        var found = Set(details.floorNames?.keys.map { $0 } ?? [])
        for reference in workspace.project(projectID)?.references ?? [] {
            let organization = workspace.organization(for:reference)
            if let level = organization?.level { found.insert(level) }
            for room in workspace.scanSummaries[reference.id]?.roomDetails ?? [] {
                found.insert(organization?.storyLevels?[room.story] ?? organization?.level ?? room.story)
            }
        }
        return found.sorted()
    }
    var body:some View {
        NavigationStack {
            Form {
                Section("Floors") {
                    ForEach(levels,id:\.self) { level in
                        TextField(StoryNaming.localizedName(for:level,locale:locale),text:Binding(get:{ details.floorNames?[level] ?? "" },set:{ value in
                            if details.floorNames == nil { details.floorNames = [:] }
                            let clean = value.trimmingCharacters(in:.whitespacesAndNewlines)
                            if clean.isEmpty { details.floorNames?.removeValue(forKey:level) }
                            else { details.floorNames?[level] = value }
                        }))
                        .accessibilityLabel(StoryNaming.localizedName(for:level,locale:locale))
                    }
                }
                Section {
                    Stepper(value:$newLevel,in:-100...1000) { Text(StoryNaming.localizedName(for:newLevel,locale:locale)) }
                    Button("Add floor",systemImage:"plus") {
                        if details.floorNames == nil { details.floorNames = [:] }
                        details.floorNames?[newLevel] = StoryNaming.localizedName(for:newLevel,locale:locale)
                    }
                    Text("Names apply to project views and photo folders. Scan geometry and original story indices stay unchanged.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Edit floors")
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement:.confirmationAction) { Button("Save") {
                        do { try workspace.saveDetails(details,projectID:projectID,expected:baseline); dismiss() }
                        catch { message = error.localizedDescription }
                    }.disabled(!details.valid) }
                }
                .onAppear { if !loaded { baseline = workspace.project(projectID)?.details; details = baseline ?? .init(); loaded = true } }
                .alert("Project details not saved",isPresented:Binding(get:{ message != nil },set:{ if !$0 { message = nil } })) { Button("OK") { message = nil } } message:{ Text(message ?? "") }
        }
    }
}

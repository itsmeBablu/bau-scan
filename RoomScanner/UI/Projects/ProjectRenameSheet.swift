import SwiftUI

struct ProjectRenameSheet:View {
    let project:RenovationProject
    @Environment(RenovationWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @State private var name:String
    @State private var failure:String?
    init(project:RenovationProject) { self.project = project; _name = State(initialValue:project.name) }
    var body:some View {
        NavigationStack {
            Form {
                TextField("Project name",text:$name).accessibilityIdentifier("project.rename.name")
                if let failure { Text(failure).foregroundStyle(DS.ColorToken.error.color) }
            }.navigationTitle("Rename project")
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement:.confirmationAction) {
                        Button("Save") {
                            if workspace.renameProject(project.id,to:name) { dismiss() }
                            else { failure = workspace.error }
                        }.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || name.count > 240)
                    }
                }
        }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }
}

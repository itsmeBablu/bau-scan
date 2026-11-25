import SwiftUI

struct MacDesignDetail: View {
    let reference: DesignRef
    let root: URL
    @State private var document: SceneEditDocument?
    @State private var error: String?
    var body: some View {
        Group {
            if let document { StudioProjectView(seed:document,storageRoot:root) }
            else if let error { ContentUnavailableView("Could not open design",systemImage:"exclamationmark.triangle",description:Text(error)) }
            else { ProgressView("Opening Studio…") }
        }.task(id:reference.id) {
            do {
                let source = reference.source,id = reference.sourceID,root = root
                document = try await Task.detached {
                    guard let document = try SceneEditStore.read(SceneEditStore.url(root:root,source:source,id:id),source:source,id:id) else { throw CocoaError(.fileNoSuchFile) }
                    return document
                }.value
            } catch { self.error = error.localizedDescription }
        }
    }
}

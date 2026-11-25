import SwiftUI

struct LibraryProblemRows: View {
    @Environment(RoomStore.self) private var store
    var reveal: ((URL) -> Void)? = nil
    @State private var deleting: LibraryProblem?
    @State private var error: String?
    var body: some View {
        ForEach(store.libraryProblems) { problem in
            DisclosureGroup(problem.url.deletingPathExtension().lastPathComponent) {
                Text(problem.reason.title)
                Text(problem.detail).font(.caption).textSelection(.enabled)
                Button("Retry") { store.retry(problem) }
                if let reveal { Button("Reveal") { reveal(problem.url) } }
                else { ShareLink("Reveal",item:problem.url) }
                Button("Delete",role:.destructive) { deleting = problem }
            }
        }
        .confirmationDialog("Delete",isPresented:Binding(get:{ deleting != nil },set:{ if !$0 { deleting = nil } })) {
            Button("Delete",role:.destructive) {
                if let deleting { do { try store.delete(deleting) } catch { self.error = error.localizedDescription } }
                deleting = nil
            }
            Button("Cancel",role:.cancel) { deleting = nil }
        }
        .alert("Error",isPresented:Binding(get:{ error != nil },set:{ if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
}

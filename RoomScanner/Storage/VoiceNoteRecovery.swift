import Foundation

/// Uses the approved notes format for a local durable outbox, separate from scans.
enum VoiceNoteRecovery {
    static func root() throws -> URL {
        try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true)
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "dWalkScan")
            .appendingPathComponent("VoiceNoteRecovery")
    }
    static func stage(_ note: ARNote,audio: Data,at root: URL) throws {
        try ARNoteStore.update(root:root,projectID:note.projectID,audio:[note.id:audio]) { index in
            guard !index.notes.contains(where:{ $0.id == note.id }) else { return }
            var copy = note; copy.number = try index.nextNumber(roomID:copy.roomID)
            copy.audioFileName = copy.stem+".m4a"; index.notes.append(copy)
        }
    }
    static func recover(projectID: UUID,from recoveryRoot: URL,to destination: URL,references: [ProjectReference]) throws {
        let library = try ARNoteStore.read(root:recoveryRoot,projectID:projectID),allowed = Set(references)
        for original in library.index.notes where allowed.contains(original.reference) {
            try Task.checkCancellation()
            guard let audio = library.audio[original.id] else { throw CocoaError(.fileNoSuchFile) }
            try ARNoteStore.update(root:destination,projectID:projectID,audio:[original.id:audio]) { index in
                guard !index.notes.contains(where:{ $0.id == original.id }) else { return }
                var note = original; note.number = try index.nextNumber(roomID:note.roomID)
                note.audioFileName = note.stem+".m4a"; index.notes.append(note)
            }
            // Only remove the outbox copy after the destination transaction succeeds.
            try ARNoteStore.update(root:recoveryRoot,projectID:projectID) { $0.notes.removeAll { $0.id == original.id } }
        }
    }
}

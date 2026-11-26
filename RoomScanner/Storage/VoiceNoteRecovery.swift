import Foundation

/// Uses the approved notes format for a local durable outbox, separate from scans.
enum VoiceNoteRecovery {
    static func root() throws -> URL {
        try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true)
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "dWalkScan")
            .appendingPathComponent("VoiceNoteRecovery")
    }
    static func stage(_ note: ARNote,audio: Data,at root: URL) throws {
        try ARNoteStore.update(root:root,projectID:note.projectID,audio:[note.id:audio],replaceAudio:false) { index in
            if let existing = index.notes.first(where:{ $0.id == note.id }) {
                guard existing.reference == note.reference else { throw CocoaError(.fileWriteFileExists) }
                return
            }
            var copy = note; copy.number = try index.nextNumber(roomID:copy.roomID)
            copy.audioFileName = copy.stem+".m4a"; index.notes.append(copy)
        }
    }
    static func recover(projectID: UUID,from recoveryRoot: URL,to destination: URL,references: [ProjectReference]) throws {
        let library = try ARNoteStore.read(root:recoveryRoot,projectID:projectID),allowed = Set(references)
        for original in library.index.notes where allowed.contains(original.reference) {
            try Task.checkCancellation()
            guard let audio = library.audio[original.id] else { throw CocoaError(.fileNoSuchFile) }
            if original.audioRevision == true {
                _ = try ARNoteStore.upsertAudio(original,audio:audio,root:destination)
            } else {
            try ARNoteStore.update(root:destination,projectID:projectID,audio:[original.id:audio],replaceAudio:false) { index in
                if let existing = index.notes.first(where:{ $0.id == original.id }) {
                    guard existing.reference == original.reference else { throw CocoaError(.fileWriteFileExists) }
                    return
                }
                var note = original; note.number = try index.nextNumber(roomID:note.roomID)
                note.audioFileName = note.stem+".m4a"; index.notes.append(note)
            }
            }
            // Only remove the outbox copy after the destination transaction succeeds.
            try ARNoteStore.update(root:recoveryRoot,projectID:projectID) { $0.notes.removeAll { $0.id == original.id && $0.modifiedAt == original.modifiedAt && $0.audioModifiedAt == original.audioModifiedAt } }
        }
    }
    static func stageRevision(_ note:ARNote,audio:Data,at root:URL) throws {
        var revision = note; revision.audioRevision = true; revision.audioModifiedAt = note.audioModifiedAt ?? note.modifiedAt ?? note.createdAt
        _ = try ARNoteStore.upsertAudio(revision,audio:audio,root:root)
    }
    /// Replacement is atomic. Keep the outbox until destination commit succeeds.
    static func publishRevision(_ note:ARNote,audio:Data,to destination:URL,outbox:URL) throws -> ARNote {
        try stageRevision(note,audio:audio,at:outbox)
        let library = try ARNoteStore.read(root:outbox,projectID:note.projectID)
        guard let revision = library.index.notes.first(where:{ $0.id == note.id }),let bytes = library.audio[note.id] else { throw CocoaError(.fileNoSuchFile) }
        let saved = try ARNoteStore.upsertAudio(revision,audio:bytes,root:destination)
        try ARNoteStore.update(root:outbox,projectID:note.projectID) { $0.notes.removeAll { $0.id == revision.id && $0.modifiedAt == revision.modifiedAt && $0.audioModifiedAt == revision.audioModifiedAt } }
        return saved
    }
}

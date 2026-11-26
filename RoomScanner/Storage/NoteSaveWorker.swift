import Foundation

/// Shared durable note-save boundary. These writes deliberately finish once
/// started rather than being cancelled with an editor. UI owners still fence late
/// presentation and keep drafts on failure. No audio/camera session ownership.
enum NoteSaveWorker {
    typealias Failure = VoiceNoteRecovery.Failure

    static func text(_ note:ARNote,expected:ARNote? = nil,root:URL) async throws -> ARNote {
        try await Task.detached(priority:.utility) {
            let saved = try ARNoteStore.upsertText(note,root:root,expected:expected)
            let current = try reloaded(saved,root:root)
            guard current.text == note.text,current.title == note.title,current.status == note.status else { throw ARNoteStore.TextConflict.stale }
            return current
        }.value
    }

    static func audioRevision(_ note:ARNote,audio:Data,root:URL,outbox:URL) async throws -> ARNote {
        try await Task.detached(priority:.utility) {
            let saved = try VoiceNoteRecovery.publishRevision(note,audio:audio,to:root,outbox:outbox)
            let current = try reloaded(saved,root:root)
            let requested = note.audioModifiedAt ?? note.modifiedAt ?? note.createdAt
            guard current.audioModifiedAt == requested else { throw Failure.supersededAudio }
            guard try ARNoteStore.audio(for:current,root:root) == audio else { throw Failure.supersededAudio }
            return current
        }.value
    }

    static func newRecording(_ note:ARNote,audio:Data,root:URL,outbox:URL) async throws -> ARNote {
        try await Task.detached(priority:.utility) {
            try VoiceNoteRecovery.stage(note,audio:audio,at:outbox)
            try VoiceNoteRecovery.recover(projectID:note.projectID,from:outbox,to:root,references:[note.reference],noteIDs:[note.id])
            let current = try reloaded(note,root:root)
            guard try ARNoteStore.audio(for:current,root:root) == audio else { throw Failure.supersededAudio }
            return current
        }.value
    }

    private static func reloaded(_ expected:ARNote,root:URL) throws -> ARNote {
        guard let current = try ARNoteStore.index(root:root,projectID:expected.projectID).notes.first(where:{ $0.id == expected.id }),
              current.reference == expected.reference else { throw CocoaError(.fileNoSuchFile) }
        return current
    }
}

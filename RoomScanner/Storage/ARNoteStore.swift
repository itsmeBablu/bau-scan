import Foundation

/// Local, versioned project sidecar. No audio is uploaded or placed inside scan packages.
enum ARNoteStore {
    static func removeWrittenText(_ expected:ARNote,root:URL) throws -> ARNoteIndex {
        try update(root:root,projectID:expected.projectID) { index in
            guard let i = index.notes.firstIndex(where:{ $0.id == expected.id }),index.notes[i].reference == expected.reference else { throw CocoaError(.fileNoSuchFile) }
            guard index.notes[i].text == expected.text,index.notes[i].title == expected.title else { throw TextConflict.stale }
            if index.notes[i].audioFileName == nil && index.notes[i].transcript == nil { index.notes.remove(at:i) }
            else { index.notes[i].text = ""; index.notes[i].title = nil; index.notes[i].modifiedAt = Date() }
        }
    }
    enum TextConflict: LocalizedError {
        case stale
        var errorDescription: String? { AppLanguage.text("This note changed elsewhere. Your draft was not saved. Reload the latest note before retrying.") }
    }
    static func upsertText(_ note:ARNote,root:URL,expected:ARNote? = nil) throws -> ARNote {
        if let expected {
            guard expected.id == note.id,expected.projectID == note.projectID,expected.reference == note.reference else { throw CocoaError(.fileWriteNoPermission) }
        }
        let index = try update(root:root,projectID:note.projectID) { value in
            var copy = note
            if let i = value.notes.firstIndex(where:{ $0.id == note.id }) {
                let old = value.notes[i]
                guard old.reference == note.reference else { throw CocoaError(.fileWriteFileExists) }
                let incomingDate = note.modifiedAt ?? note.createdAt,storedDate = old.modifiedAt ?? old.createdAt
                guard incomingDate >= storedDate,
                      incomingDate != storedDate || (note.text == old.text && note.title == old.title && note.status == old.status) else { throw TextConflict.stale }
                if let expected {
                    guard old.text == expected.text,old.title == expected.title,old.status == expected.status else { throw TextConflict.stale }
                }
                copy.number = old.number; copy.audioFileName = old.audioFileName; copy.audioDuration = old.audioDuration
                copy.audioModifiedAt = old.audioModifiedAt; copy.partial = old.partial; copy.transcriptState = old.transcriptState
                copy.transcript = old.transcript; copy.retainAudio = old.retainAudio
                value.notes[i] = copy
            } else {
                guard expected == nil else { throw CocoaError(.fileNoSuchFile) }
                copy.number = try value.nextNumber(roomID:copy.roomID); value.notes.append(copy)
            }
        }
        guard let saved = index.notes.first(where:{ $0.id == note.id }) else { throw CocoaError(.fileWriteUnknown) }; return saved
    }
    private enum RevisionError:Error { case stale }
    static func upsertAudio(_ note:ARNote,audio:Data,root:URL) throws -> ARNote {
        do {
        let index = try update(root:root,projectID:note.projectID,audio:[note.id:audio]) { value in
            let audioDate = note.audioModifiedAt ?? note.modifiedAt ?? note.createdAt
            var copy = note; copy.audioModifiedAt = audioDate
            if let i = value.notes.firstIndex(where:{ $0.id == note.id }) {
                guard value.notes[i].reference == note.reference else { throw CocoaError(.fileWriteFileExists) }
                let old = value.notes[i]
                let previousAudioDate = old.audioModifiedAt ?? (old.audioFileName == nil ? .distantPast : old.modifiedAt ?? old.createdAt)
                guard audioDate >= previousAudioDate else { throw RevisionError.stale }
                if (old.modifiedAt ?? old.createdAt) > (note.modifiedAt ?? note.createdAt) {
                    copy.text = old.text; copy.title = old.title; copy.status = old.status; copy.modifiedAt = old.modifiedAt
                }
                copy.number = value.notes[i].number; copy.audioFileName = copy.stem+".m4a"; value.notes[i] = copy
            } else { copy.number = try value.nextNumber(roomID:copy.roomID); copy.audioFileName = copy.stem+".m4a"; value.notes.append(copy) }
        }
        guard let saved = index.notes.first(where:{ $0.id == note.id }) else { throw CocoaError(.fileWriteUnknown) }; return saved
        } catch RevisionError.stale {
            guard let current = try index(root:root,projectID:note.projectID).notes.first(where:{ $0.id == note.id }) else { throw CocoaError(.fileNoSuchFile) }
            return current
        }
    }
    struct Library { var index: ARNoteIndex; var audio: [UUID:Data] }
    private static func validateParents(root: URL,projectID: UUID) throws {
        let projects = root.appendingPathComponent("Projects")
        for folder in [projects,projects.appendingPathComponent(projectID.uuidString)] where FileManager.default.fileExists(atPath:folder.path) {
            let info = try folder.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
            guard info.isDirectory == true,info.isSymbolicLink != true else { throw CocoaError(.fileReadNoPermission) }
        }
    }
    static func index(root: URL,projectID: UUID) throws -> ARNoteIndex {
        try validateParents(root:root,projectID:projectID)
        let directory = url(root:root,projectID:projectID)
        guard FileManager.default.fileExists(atPath:directory.deletingLastPathComponent().path) else { return .init(projectID:projectID) }
        return try RoomPackage.coordinatedRead(at:directory.deletingLastPathComponent()) { parent in
            let target = parent.appendingPathComponent(directory.lastPathComponent),backup = parent.appendingPathComponent(".ARNotes-backup")
            return try load(!FileManager.default.fileExists(atPath:target.path) && FileManager.default.fileExists(atPath:backup.path) ? backup : target,projectID:projectID,includeAudio:false).index
        }
    }
    static func url(root: URL,projectID: UUID) -> URL {
        root.appendingPathComponent("Projects").appendingPathComponent(projectID.uuidString).appendingPathComponent("ARNotes")
    }
    static func read(root: URL,projectID: UUID) throws -> Library {
        try validateParents(root:root,projectID:projectID)
        let directory = url(root:root,projectID:projectID)
        guard FileManager.default.fileExists(atPath:directory.deletingLastPathComponent().path) else {
            return .init(index:.init(projectID:projectID),audio:[:])
        }
        return try RoomPackage.coordinatedRead(at:directory.deletingLastPathComponent()) { parent in
            let target = parent.appendingPathComponent(directory.lastPathComponent)
            let backup = parent.appendingPathComponent(".ARNotes-backup")
            return try load(!FileManager.default.fileExists(atPath:target.path) && FileManager.default.fileExists(atPath:backup.path) ? backup : target,projectID:projectID)
        }
    }
    /// Read only the requested clip; unrelated audio is not loaded for inline playback.
    static func audio(for expected:ARNote,root:URL) throws -> Data {
        try validateParents(root:root,projectID:expected.projectID)
        let directory = url(root:root,projectID:expected.projectID)
        return try RoomPackage.coordinatedRead(at:directory.deletingLastPathComponent()) { parent in
            let target = parent.appendingPathComponent(directory.lastPathComponent)
            let backup = parent.appendingPathComponent(".ARNotes-backup")
            let source = !FileManager.default.fileExists(atPath:target.path) && FileManager.default.fileExists(atPath:backup.path) ? backup : target
            let library = try load(source,projectID:expected.projectID,includeAudio:false)
            guard let current = library.index.notes.first(where:{ $0.id == expected.id }),
                  current.reference == expected.reference,current.audioModifiedAt == expected.audioModifiedAt,
                  current.audioFileName == expected.audioFileName,let path = current.audioPath else { throw CocoaError(.fileNoSuchFile) }
            let bytes = try SafePackageRead.data(source.appendingPathComponent(path),root:source,maximum:ARNoteIndex.maximumClipBytes,preflight:false)
            guard bytes.count >= 12,bytes.subdata(in:4..<8) == Data("ftyp".utf8) else { throw CocoaError(.fileReadCorruptFile) }
            return bytes
        }
    }
    /// Re-read/edit/replace in one coordinated operation to prevent lost updates.
    /// Audio is keyed by note ID; callers cannot supply an arbitrary file path.
    @discardableResult static func update(root: URL,projectID: UUID,audio: [UUID:Data] = [:],
                                         replaceAudio: Bool = true,
                                         edit: (inout ARNoteIndex) throws -> Void) throws -> ARNoteIndex {
        try validateParents(root:root,projectID:projectID)
        let directory = url(root:root,projectID:projectID),fm = FileManager.default
        try fm.createDirectory(at:directory.deletingLastPathComponent(),withIntermediateDirectories:true)
        try validateParents(root:root,projectID:projectID)
        var result = ARNoteIndex(projectID:projectID)
        try RoomPackage.coordinatedWrite(at:directory,options:.forReplacing) { target in
            let backup = target.deletingLastPathComponent().appendingPathComponent(".ARNotes-backup")
            if !fm.fileExists(atPath:target.path),fm.fileExists(atPath:backup.path) {
                _ = try load(backup,projectID:projectID)
                try fm.moveItem(at:backup,to:target)
            }
            var library = try load(target,projectID:projectID)
            try edit(&library.index); try library.index.validate()
            let audioIDs = Set(library.index.notes.filter { $0.audioFileName != nil }.map(\.id))
            guard Set(audio.keys).isSubset(of:audioIDs) else { throw CocoaError(.fileWriteInvalidFileName) }
            if !replaceAudio {
                for (id,bytes) in audio {
                    if let existing = library.audio[id],existing != bytes { throw CocoaError(.fileWriteFileExists) }
                }
            }
            library.audio.merge(audio) { _,new in new }
            library.audio = library.audio.filter { audioIDs.contains($0.key) }
            try validateAudio(library)
            let staging = target.deletingLastPathComponent().appendingPathComponent(".notes-stage-"+UUID().uuidString)
            try fm.createDirectory(at:staging,withIntermediateDirectories:true)
            defer { try? fm.removeItem(at:staging) }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let indexData = try encoder.encode(library.index)
            guard indexData.count <= 32*1_048_576 else { throw CocoaError(.fileWriteOutOfSpace) }
            for note in library.index.notes {
                let folder = staging.appendingPathComponent(note.roomFolder)
                try fm.createDirectory(at:folder,withIntermediateDirectories:true)
                try encoder.encode(note).write(to:staging.appendingPathComponent(note.jsonPath),options:.atomic)
                if let path = note.audioPath,let data = library.audio[note.id] {
                    try data.write(to:staging.appendingPathComponent(path),options:.atomic)
                }
            }
            try indexData.write(to:staging.appendingPathComponent("index-v1.json"),options:.atomic)
            try SafePackageRead.validate(staging,entries:30_001,total:128*1_048_576)
            let existed = fm.fileExists(atPath:target.path)
            if fm.fileExists(atPath:backup.path) { try fm.removeItem(at:backup) }
            if existed { try fm.moveItem(at:target,to:backup) }
            do { try fm.moveItem(at:staging,to:target) }
            catch {
                if existed { try fm.moveItem(at:backup,to:target) }
                throw error
            }
            if existed { try? fm.removeItem(at:backup) }
            result = library.index
        }
        return result
    }
    private static func validateAudio(_ library: Library) throws {
        var bytes = 0
        for note in library.index.notes where note.audioFileName != nil {
            guard let data = library.audio[note.id],data.count >= 12,data.count <= ARNoteIndex.maximumClipBytes,
                  data.subdata(in:4..<8) == Data("ftyp".utf8) else { throw CocoaError(.fileReadCorruptFile) }
            bytes += data.count
            guard bytes <= ARNoteIndex.maximumAudioBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        }
    }
    private static func load(_ directory: URL,projectID: UUID,includeAudio: Bool = true) throws -> Library {
        let fm = FileManager.default,indexFile = directory.appendingPathComponent("index-v1.json")
        guard fm.fileExists(atPath:directory.path) else { return .init(index:.init(projectID:projectID),audio:[:]) }
        // An existing but incomplete directory is corrupt; never overwrite it as an empty library.
        let attributes = try directory.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
        guard attributes.isDirectory == true,attributes.isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
        try SafePackageRead.validate(directory,entries:30_001,total:128*1_048_576)
        // Resolve trusted ancestors such as macOS /var -> /private/var, but reject linked assets below this root.
        let base = directory.resolvingSymlinksInPath().standardizedFileURL
        func data(_ path: URL,maximum: Int) throws -> Data {
            let resolved = path.resolvingSymlinksInPath().standardizedFileURL
            let info = try path.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
            guard resolved.path.hasPrefix(base.path+"/"),info.isRegularFile == true,info.isSymbolicLink != true,
                  let size = info.fileSize,size <= maximum else { throw CocoaError(.fileReadCorruptFile) }
            return try Data(contentsOf:path)
        }
        let index = try JSONDecoder().decode(ARNoteIndex.self,from:data(indexFile,maximum:32*1_048_576))
        try index.validate()
        guard index.projectID == projectID else { throw CocoaError(.fileReadCorruptFile) }
        if !includeAudio { return .init(index:index,audio:[:]) }
        var library = Library(index:index,audio:[:]),total = 0
        for note in index.notes {
            // The index is authoritative; redundant per-note JSON is for portable handoff only.
            if let path = note.audioPath {
                let clip = try data(directory.appendingPathComponent(path),maximum:ARNoteIndex.maximumClipBytes)
                total += clip.count
                guard total <= ARNoteIndex.maximumAudioBytes else { throw CocoaError(.fileReadCorruptFile) }
                library.audio[note.id] = clip
            }
        }
        try validateAudio(library)
        return library
    }
}

import Foundation

/// Shared file-level deduplication for the legacy scan export folders.
/// Identical bytes keep their original filename; changed files get a numbered version.
enum SavedExportFiles {
    enum PublicationStage { case afterSourceHash, beforeCopy, afterCopy }

    static func store(_ source:URL,in folder:URL,
                      fault:(PublicationStage) throws -> Void = { _ in }) throws -> URL {
        try Task.checkCancellation()
        let info = try source.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard info.isRegularFile == true,info.isSymbolicLink != true,let bytes = info.fileSize,
              (0...1_073_741_824).contains(bytes),!source.lastPathComponent.hasPrefix(".") else { throw CocoaError(.fileReadCorruptFile) }
        let directory = try folder.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
        guard directory.isDirectory == true,directory.isSymbolicLink != true else { throw CocoaError(.fileWriteNoPermission) }
        var output:URL?
        try RoomPackage.coordinatedWrite(at:folder,options:.forMerging) { root in
            try Task.checkCancellation()
            let revision = try SavedFileRevision(source)
            let hash = try ExportChecksum.sha256(source)
            try fault(.afterSourceHash)
            func validateSource() throws {
                try Task.checkCancellation()
                guard try SavedFileRevision(source) == revision else { throw CocoaError(.fileReadCorruptFile) }
            }
            try validateSource()
            let files = try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey],options:.skipsHiddenFiles)
            guard files.count <= 10_000 else { throw CocoaError(.fileReadTooLarge) }
            for file in files.sorted(by:{ $0.lastPathComponent < $1.lastPathComponent }) where file.pathExtension.lowercased() == source.pathExtension.lowercased() {
                try Task.checkCancellation()
                let attributes = try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
                if attributes.isRegularFile == true,attributes.isSymbolicLink != true,attributes.fileSize == bytes,
                   try ExportChecksum.sha256(file) == hash { try validateSource(); output = file; return }
            }
            let base = ArchivePath.component(source.deletingPathExtension().lastPathComponent),ext = source.pathExtension
            let suffix = ext.isEmpty ? "" : "."+ext
            var name = base+suffix,number = 2
            let names = Set(files.map { $0.lastPathComponent.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX")) })
            while names.contains(name.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX"))) || FileManager.default.fileExists(atPath:root.appendingPathComponent(name).path) {
                name = base+" - \(number)"+suffix; number += 1
                guard number <= 10_000 else { throw CocoaError(.fileWriteFileExists) }
            }
            let target = root.appendingPathComponent(name),staging = try PackageReplacement.staging(for:target)
            defer { try? FileManager.default.removeItem(at:staging) }
            try fault(.beforeCopy)
            try validateSource()
            try FileManager.default.copyItem(at:source,to:staging)
            try fault(.afterCopy)
            guard try ExportChecksum.sha256(staging) == hash else { throw CocoaError(.fileReadCorruptFile) }
            try validateSource(); try PackageReplacement.commit(staging,to:target); output = target
        }
        guard let output else { throw CocoaError(.fileWriteUnknown) }; return output
    }
}

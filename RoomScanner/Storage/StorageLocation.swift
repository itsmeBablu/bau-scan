import Foundation

/// Storage root: iCloud container or local directory. Associated
/// paths `Rooms/` and `Exports/` derive from it.
struct StorageLocation: Equatable {
    enum Kind: Equatable { case local, iCloud }

    let kind: Kind
    /// Directory containing `Rooms/` and `Exports/` (= container `Documents/` folder).
    let documentsURL: URL

    var roomsURL: URL { documentsURL.appendingPathComponent(FileLayout.roomsFolder, isDirectory: true) }
    var exportsURL: URL { documentsURL.appendingPathComponent(FileLayout.exportsFolder, isDirectory: true) }
    var housesURL: URL { documentsURL.appendingPathComponent(FileLayout.housesFolder, isDirectory: true) }

    func packageURL(for id: UUID) -> URL {
        roomsURL.appendingPathComponent(id.uuidString).appendingPathExtension(FileLayout.packageExtension)
    }

    func housePackageURL(for id: UUID) -> URL {
        housesURL.appendingPathComponent(id.uuidString).appendingPathExtension(FileLayout.housePackageExtension)
    }

    /// Creates `Rooms/` and `Exports/` directories if needed.
    func prepare() throws {
        for url in [roomsURL, exportsURL, housesURL] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// App Documents directory (iOS: visible in Files app; macOS: sandbox container).
    static func local(fileManager: FileManager = .default) -> StorageLocation {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return StorageLocation(kind: .local, documentsURL: docs)
    }

    /// Ephemeral storage root for unit tests.
    static func temporary() -> StorageLocation {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoomScanner-\(UUID().uuidString)", isDirectory: true)
        return StorageLocation(kind: .local, documentsURL: url)
    }
}

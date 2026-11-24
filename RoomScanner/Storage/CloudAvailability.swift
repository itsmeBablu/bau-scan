import Foundation

/// iCloud Drive container resolution and local → iCloud migration.
/// `url(forUbiquityContainerIdentifier:)` can block: always execute off main thread.
enum CloudAvailability {
    static let containerIdentifier = "iCloud.io.github.itsmebablu.dwalkscan"
    /// New installations remain local. Existing cloud libraries are detected on a worker.
    static let preferenceKey = "RoomScannerUseICloud"

    static var isEnabledByUser: Bool {
        UserDefaults.standard.bool(forKey: preferenceKey)
    }

    /// Is an iCloud account signed in on the device?
    static var isSignedIn: Bool { FileManager.default.ubiquityIdentityToken != nil }

    /// `Documents/` container folder (public 'dWalkScan' folder in Files / Finder).
    static func documentsURL(containerURL: URL) -> URL {
        containerURL.appendingPathComponent("Documents", isDirectory: true)
    }

    /// iCloud location, or `nil` if signed out, container absent, or disabled.
    /// Must be called from a detached background task.
    nonisolated static func resolveLocation() -> StorageLocation? {
        if UserDefaults.standard.object(forKey:preferenceKey) != nil && !isEnabledByUser { return nil }
        guard isSignedIn,
              let container = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) else { return nil }
        if UserDefaults.standard.object(forKey:preferenceKey) == nil {
            let root = documentsURL(containerURL:container)
            let hasExisting = ["Rooms","Houses"].contains { directory in
                ((try? FileManager.default.contentsOfDirectory(at:root.appendingPathComponent(directory),includingPropertiesForKeys:nil,options:.skipsHiddenFiles)) ?? []).contains { ["roomscan","housescan"].contains($0.pathExtension) }
            }
            // Preserve access to an existing cloud library; never migrate local files at launch.
            guard hasExisting else { return nil }
            UserDefaults.standard.set(true,forKey:preferenceKey)
        }
        guard isEnabledByUser else { return nil }
        return StorageLocation(kind: .iCloud, documentsURL: documentsURL(containerURL: container))
    }

    /// Migrates local packages and exports to iCloud if not already present
    /// (`setUbiquitous`). Packages already present in iCloud are preserved:
    /// the local copy is retained without overwriting. Returns count moved.
    @discardableResult
    nonisolated static func migrate(from local: StorageLocation, to cloud: StorageLocation, fileManager fm: FileManager = .default) throws -> Int {
        guard local.kind == .local, cloud.kind == .iCloud, local.documentsURL != cloud.documentsURL else { return 0 }
        try cloud.prepare()
        var moved = 0
        for (src, dst) in [(local.roomsURL, cloud.roomsURL), (local.exportsURL, cloud.exportsURL)] {
            guard fm.fileExists(atPath: src.path) else { continue }
            for item in try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                let target = dst.appendingPathComponent(item.lastPathComponent)
                guard !fm.fileExists(atPath: target.path) else { continue }
                try fm.setUbiquitous(true, itemAt: item, destinationURL: target)
                moved += 1
            }
        }
        return moved
    }
}

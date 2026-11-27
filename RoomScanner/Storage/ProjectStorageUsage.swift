import Foundation

struct ProjectStorageEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let isUnsorted: Bool
    let bytes: Int64
    let layouts: Int
    let floors: Int
    let totalAreaM2: Double
    let approvedCount: Int
    let acceptedCount: Int

    func displayName(locale: Locale) -> String {
        isUnsorted ? AppLanguage.text("Unsorted", locale: locale) : name
    }

    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

enum ProjectStorageUsage {
    /// Computes read-only disk usage and real project metrics across connected libraries.
    static func load(roots: [String: URL], catalogueRoot: URL, locale: Locale = AppLanguage.locale) throws -> [ProjectStorageEntry] {
        try Task.checkCancellation()
        let index = try ProjectIndexStore.read(root: catalogueRoot)
        let entries = try index.projects.map { project -> ProjectStorageEntry in
            try Task.checkCancellation()
            return try entry(for: project, index: index, roots: roots, catalogueRoot: catalogueRoot)
        }
        return entries.sorted { lhs, rhs in
            if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
            let comparison = lhs.displayName(locale: locale).localizedStandardCompare(rhs.displayName(locale: locale))
            return comparison == .orderedSame ? lhs.id.uuidString < rhs.id.uuidString : comparison == .orderedAscending
        }
    }

    static func storageBytes(for project: RenovationProject, roots: [String: URL], catalogueRoot: URL) throws -> Int64 {
        var targets = Set<URL>()
        let projectFolder = catalogueRoot.appendingPathComponent("Projects/\(project.id.uuidString)", isDirectory: true).standardizedFileURL
        targets.insert(projectFolder)
        for ref in project.references {
            guard let target = targetURL(for: ref, roots: roots) else { continue }
            targets.insert(target.standardizedFileURL)
        }
        var total: Int64 = 0
        for url in targets {
            try Task.checkCancellation()
            total += try byteSize(at: url)
        }
        return total
    }

    private static func entry(for project: RenovationProject, index: ProjectIndex, roots: [String: URL], catalogueRoot: URL) throws -> ProjectStorageEntry {
        let bytes = try storageBytes(for: project, roots: roots, catalogueRoot: catalogueRoot)
        let layouts = project.references.count
        var floors = 0
        var totalAreaM2 = 0.0
        var approvedCount = index.distanceChecks?.filter { $0.projectID == project.id }.count ?? 0
        var acceptedCount = 0

        var seenScans = Set<String>()
        for ref in project.references {
            try Task.checkCancellation()
            guard let url = targetURL(for: ref, roots: roots) else { continue }
            let scanKey = "\(ref.library):\(ref.itemID.uuidString)"
            switch ref.kind {
            case .house:
                guard seenScans.insert(scanKey).inserted else { continue }
                if let house = try? HousePackage.readHouse(from: url) {
                    let summary = ProjectScanSummary(house: house)
                    floors += summary.stories
                    totalAreaM2 += summary.floorArea
                }
            case .room:
                guard seenScans.insert(scanKey).inserted else { continue }
                if let plan = try? RoomPackage.readPlan(from: url) {
                    let summary = ProjectScanSummary(house: House(room: plan))
                    floors += summary.stories
                    totalAreaM2 += summary.floorArea
                }
            case .technicalRoom:
                guard seenScans.insert(scanKey).inserted else { continue }
                if let data = try? SafePackageRead.data(url.appendingPathComponent("recognition.json"), root: url, maximum: 1_048_576),
                   let review = try? JSONDecoder().decode(TechnicalMEPReview.self, from: data) {
                    acceptedCount += review.suggestions.filter { $0.status == .accepted }.count
                }
                if let data = try? SafePackageRead.data(url.appendingPathComponent("survey.json"), root: url, maximum: 8 * 1_048_576),
                   let survey = try? JSONDecoder().decode(TechnicalAlignmentSurvey.self, from: data) {
                    approvedCount += survey.checkpoints.filter(\.accepted).count
                }
            case .designRoom, .designHouse, .designTechnical:
                continue
            }
        }

        return ProjectStorageEntry(
            id: project.id,
            name: project.name,
            isUnsorted: project.isUnsorted,
            bytes: bytes,
            layouts: layouts,
            floors: floors,
            totalAreaM2: totalAreaM2,
            approvedCount: approvedCount,
            acceptedCount: acceptedCount
        )
    }

    private static func targetURL(for ref: ProjectReference, roots: [String: URL]) -> URL? {
        guard let root = roots[ref.library] else { return nil }
        switch ref.kind {
        case .room:
            return root.appendingPathComponent("Rooms/\(ref.itemID.uuidString).roomscan")
        case .house:
            return root.appendingPathComponent("Houses/\(ref.itemID.uuidString).housescan")
        case .technicalRoom:
            return root.appendingPathComponent("TechnicalRooms/\(ref.itemID.uuidString).technicalroom")
        case .designRoom, .designHouse, .designTechnical:
            let source: SceneEditDocument.Source = ref.kind == .designRoom ? .room : ref.kind == .designHouse ? .house : .technical
            return SceneEditStore.url(root: root, source: source, id: ref.itemID)
        }
    }

    private static func byteSize(at url: URL) throws -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return 0 }
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isSymbolicLink != true else { return 0 }
        if info.isRegularFile == true { return Int64(info.fileSize ?? 0) }
        guard info.isDirectory == true,
              let items = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var sum: Int64 = 0
        for case let file as URL in items {
            try Task.checkCancellation()
            let attrs = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard attrs?.isSymbolicLink != true, attrs?.isRegularFile == true else { continue }
            sum += Int64(attrs?.fileSize ?? 0)
        }
        return sum
    }
}

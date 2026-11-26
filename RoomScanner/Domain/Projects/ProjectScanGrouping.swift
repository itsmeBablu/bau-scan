import Foundation

/// Presentation groups; references/UUIDs remain the only scan identities.
enum ProjectScanGrouping {
    struct BuildingKey: Hashable { let name: String? }
    struct LevelKey: Hashable { let number: Int?; let otherName: String? }
    struct Building: Identifiable {
        let id: BuildingKey
        let levels: [Level]
    }
    struct Level: Identifiable {
        let id: LevelKey
        let scans: [ProjectLibraryEntry]
    }
    static func buildings(entries: [ProjectLibraryEntry], organization: [String: ScanOrganization], locale: Locale) -> [Building] {
        func compare(_ a: String, _ b: String) -> Bool {
            let order = a.compare(b, options: [.caseInsensitive, .numeric], locale: locale)
            return order == .orderedSame ? a < b : order == .orderedAscending
        }
        let grouped = Dictionary(grouping: entries) { BuildingKey(name: organization[$0.id]?.buildingName) }
        return grouped.keys.sorted {
            switch ($0.name, $1.name) {
            case let (a?, b?): return compare(a, b)
            case (_?, nil): return true
            default: return false
            }
        }.map { building in
            let levels = Dictionary(grouping: grouped[building] ?? []) { entry in
                LevelKey(number: organization[entry.id]?.level, otherName: organization[entry.id]?.otherLevelName)
            }
            let ordered = levels.keys.sorted { a, b in
                switch (a.number, b.number) {
                case let (x?, y?): return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default:
                    switch (a.otherName, b.otherName) {
                    case let (x?, y?): return compare(x, y)
                    case (_?, nil): return true
                    default: return false
                    }
                }
            }
            return Building(id: building, levels: ordered.map { level in
                Level(id: level, scans: (levels[level] ?? []).sorted { a, b in
                    let first = organization[a.id]?.number ?? Int.max, second = organization[b.id]?.number ?? Int.max
                    if first != second { return first < second }
                    if a.date != b.date { return a.date > b.date }
                    return a.id < b.id
                })
            })
        }
    }
}

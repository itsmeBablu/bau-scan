import Foundation

/// Optional catalogue metadata. Never changes scan coordinates, story indices or package names.
struct ScanOrganization: Codable, Equatable {
    var level: Int? = nil
    var otherLevelName: String? = nil
    var buildingName: String? = nil
    var zoneName: String? = nil
    var number: Int? = nil
    var kind: ProjectReference.Kind
    /// User mapping of detected story indices to building levels; geometry stays untouched.
    var storyLevels: [Int: Int]? = nil

    static let offeredLevels = Array(-3...20)

    func validate() throws {
        guard level.map({ (-100...1000).contains($0) }) ?? true,
              !(level != nil && otherLevelName != nil),
              number.map({ (1...9999).contains($0) }) ?? true,
              [otherLevelName, buildingName, zoneName].allSatisfy({ text in
                  guard let text else { return true }
                  return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= 120 &&
                      !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
              }),
              (storyLevels?.count ?? 0) <= 100,
              storyLevels?.allSatisfy({ (-100...1000).contains($0.key) && (-100...1000).contains($0.value) }) ?? true
        else { throw CocoaError(.fileReadCorruptFile) }
    }

    func levelName(locale: Locale) -> String {
        if let level { return StoryNaming.localizedName(for: level, locale: locale) }
        return otherLevelName ?? String(localized: "Unassigned level", locale: locale)
    }

    func displayName(locale: Locale) -> String {
        var parts = [levelName(locale: locale)]
        if let buildingName { parts.append(buildingName) }
        var detail = zoneName ?? ""
        if let number { detail += (detail.isEmpty ? "" : " ") + String(number) }
        if !detail.isEmpty { parts.append(detail) }
        return parts.joined(separator: " · ")
    }

    fileprivate func sameNumberScope(as other: Self) -> Bool {
        func normalized(_ value: String?) -> String {
            (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }
        return kind == other.kind && level == other.level &&
            normalized(otherLevelName) == normalized(other.otherLevelName) &&
            normalized(buildingName) == normalized(other.buildingName) && normalized(zoneName) == normalized(other.zoneName)
    }
}

extension ProjectIndex {
    /// No reservation/overwrite: callers explicitly confirm a collision or choose the suggestion.
    func numberCollisions(for value: ScanOrganization, projectID: UUID, excluding: ProjectReference? = nil) -> [ProjectReference] {
        guard let number = value.number, let project = projects.first(where: { $0.id == projectID }) else { return [] }
        return project.references.filter { reference in
            guard reference != excluding, let existing = scanOrganization?[reference.id] else { return false }
            return existing.number == number && value.sameNumberScope(as: existing)
        }.sorted { $0.id < $1.id }
    }

    func suggestedNumber(for value: ScanOrganization, projectID: UUID, excluding: ProjectReference? = nil) -> Int? {
        guard let project = projects.first(where: { $0.id == projectID }) else { return nil }
        let used = Set(project.references.compactMap { reference -> Int? in
            guard reference != excluding, let existing = scanOrganization?[reference.id], value.sameNumberScope(as: existing) else { return nil }
            return existing.number
        })
        return (1...9999).first { !used.contains($0) }
    }

    mutating func setOrganization(_ value: ScanOrganization, for reference: ProjectReference, now: Date = Date()) throws {
        try value.validate()
        guard value.kind == reference.kind, let owner = projects.firstIndex(where: { $0.references.contains(reference) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if scanOrganization == nil { scanOrganization = [:] }
        scanOrganization?[reference.id] = value
        projects[owner].modifiedAt = now
    }
}

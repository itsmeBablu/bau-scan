import Foundation

/// Suggested room name based on RoomPlan label, deduplicated
/// ('Bedroom', 'Bedroom 2', ...). Localized rendering is injected
/// for testability independent of system language.
struct RoomNaming {
    var localizedBaseName: (RoomLabel) -> String = RoomNaming.defaultBaseName

    func proposedName(for label: RoomLabel, existingNames: [String]) -> String {
        deduplicated(localizedBaseName(label), existingNames)
    }

    /// Name based on all RoomPlan sections in capture: a room may have
    /// multiple (e.g. dining room open to kitchen ⇒ 'Dining Room / Kitchen').
    /// `\.unidentified` is omitted when another section exists, duplicates removed,
    /// and a capture without identified section falls back to deduplicated generic name.
    func proposedName(for labels: [RoomLabel], existingNames: [String]) -> String {
        var kept: [RoomLabel] = []
        for label in labels where label != .unidentified && !kept.contains(label) { kept.append(label) }
        guard !kept.isEmpty else { return proposedName(for: .unidentified, existingNames: existingNames) }
        return deduplicated(kept.map(localizedBaseName).joined(separator: " / "), existingNames)
    }

    private func deduplicated(_ base: String, _ existingNames: [String]) -> String {
        guard existingNames.contains(base) else { return base }
        var n = 2
        while existingNames.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    static func defaultBaseName(_ label: RoomLabel) -> String {
        AppLanguage.text(label.localizationKey)
    }

    /// Display fallback only: preserve saved/user-entered names and scan formats.
    static func displayName(_ name:String,label:RoomLabel,locale:Locale) -> String {
        name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
            ? AppLanguage.text(label.localizationKey,locale:locale) : name
    }
}

extension RoomLabel {
    var localizationKey: String {
        switch self {
        case .livingRoom: "room.label.livingRoom"
        case .bedroom: "room.label.bedroom"
        case .bathroom: "room.label.bathroom"
        case .kitchen: "room.label.kitchen"
        case .diningRoom: "room.label.diningRoom"
        case .unidentified: "room.label.unidentified"
        }
    }
}

/// Localized labels for RoomPlan object categories ('table', 'sofa', ...);
/// fallback to capitalized raw category if no translation exists.
enum ObjectNaming {
    static func localizedName(_ category: String) -> String {
        let key = "object.\(category)"
        let s = String(localized: String.LocalizationValue(key), bundle: .main, locale: AppLanguage.locale)
        return s == key ? category.capitalized : s
    }
}

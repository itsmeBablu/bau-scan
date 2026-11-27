import Foundation

/// Groups rooms into stories based on floor elevation (D27): elevations
/// within `tolerance` form the same story; lowest story is 0.
/// Stories remain editable later — this is an initial suggestion.
struct StoryDetector {
    var tolerance: Double = 0.5

    /// Story index by room identifier.
    func stories(floorHeights: [UUID: Double]) -> [UUID: Int] {
        let sorted = floorHeights.sorted { $0.value < $1.value }
        var result: [UUID: Int] = [:]
        var currentIndex = -1
        var clusterStart = -Double.infinity
        for (id, h) in sorted {
            if h - clusterStart > tolerance { currentIndex += 1; clusterStart = h }
            result[id] = currentIndex
        }
        return result
    }

    /// Floor elevation of a scan (m, RoomPlan): first known floor, else wall bottom.
    static func floorHeight(of scan: ScanInput) -> Double {
        if let f = scan.floors.first { return Double(f.transform.translation.y) }
        let bottoms = scan.walls.map { Double($0.transform.translation.y) - Double($0.dimensions.y) / 2 }
        return bottoms.min() ?? 0
    }
}

/// Story names ('Ground floor', 'Floor 1'...), localized keys.
enum StoryNaming {
    static func localizationKey(for index: Int) -> String {
        index == 0 ? "story.ground" : index < 0 ? "story.lower %lld" : "story.upper %lld"
    }
    static func localizedName(for index: Int, locale: Locale = AppLanguage.locale) -> String {
        if index == 0 { return AppLanguage.text("story.ground",locale:locale) }
        if index < 0 {
            let basement = index == Int.min ? Int.max : -index
            return String(format:AppLanguage.text("story.lower %lld",locale:locale),locale:locale,basement)
        }
        return String(format:AppLanguage.text("story.upper %lld",locale:locale),locale:locale,index)
    }
}

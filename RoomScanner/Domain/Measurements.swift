import Foundation

/// Configurable measurement units (mm, meters, or both).
public enum MeasurementUnit: String, CaseIterable, Identifiable, Codable {
    case millimeters = "mm"
    case meters = "m"
    case both = "both"

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .millimeters: return "unit.millimeters"
        case .meters: return "unit.meters"
        case .both: return "unit.both"
        }
    }

    public var shortLabel: String {
        switch self {
        case .millimeters: return "mm"
        case .meters: return "m"
        case .both: return "mm & m"
        }
    }
}

/// Measurements derived from a `FloorPlan`. All values in meters / m².
struct RoomMeasurements: Equatable {
    struct WallMeasure: Equatable, Identifiable { let id: UUID; let length: Double; let height: Double; let confidence: Confidence }
    struct OpeningMeasure: Equatable, Identifiable {
        let id: UUID; let kind: Opening.Kind; let width: Double; let height: Double; let sillHeight: Double; let confidence: Confidence
    }
    struct ObjectMeasure: Equatable, Identifiable {
        let id: UUID; let category: String; let width: Double; let depth: Double; let height: Double; let confidence: Confidence
    }

    let floorArea: Double
    let perimeter: Double
    let ceilingHeight: ClosedRange<Double>
    let walls: [WallMeasure]
    let openings: [OpeningMeasure]
    let objects: [ObjectMeasure]

    init(plan: FloorPlan) {
        floorArea = Polygon2D.area(plan.floorPolygon)
        perimeter = plan.walls.reduce(0) { $0 + $1.length }
        ceilingHeight = plan.ceilingHeight
        walls = plan.walls.map { WallMeasure(id: $0.id, length: $0.length, height: $0.height, confidence: $0.confidence) }
        openings = plan.openings.map {
            OpeningMeasure(id: $0.id, kind: $0.kind, width: $0.width, height: $0.height, sillHeight: $0.sillHeight, confidence: $0.confidence)
        }
        objects = plan.objects.map {
            ObjectMeasure(id: $0.id, category: $0.category, width: $0.size.width, depth: $0.size.depth, height: $0.height, confidence: $0.confidence)
        }
    }

    var doors: [OpeningMeasure] { openings.filter { $0.kind == .door } }
    var windows: [OpeningMeasure] { openings.filter { $0.kind == .window } }
}

/// House measurements. The area is the **union** of rooms on the same story rather than
/// their sum, avoiding double-counting overlaps along shared walls.
struct HouseMeasurements: Equatable {
    let floorArea: Double
    let roomCount: Int
    let storyCount: Int

    init(house: House) {
        floorArea = house.stories.reduce(0) { $0 + Polygon2D.unionArea($1.rooms.map(\.floorPolygon)) }
        roomCount = house.allRooms.count
        storyCount = house.stories.count
    }
}

/// Measurement formatting for display and 2D exports: millimeters (mm)
/// and meters (m), m² to 1 decimal place, English dot-decimal standard.
enum MeasurementFormat {
    /// Formatted whole millimeters (e.g. "4,000 mm" or "4000 mm").
    static func millimeters(_ meters: Double, locale: Locale = Locale(identifier: "en_US")) -> String {
        let mm = (meters * 1000).rounded()
        let f = NumberFormatter(); f.locale = locale; f.maximumFractionDigits = 0
        return (f.string(from: mm as NSNumber) ?? "\(Int(mm))") + " mm"
    }

    /// Formatted meters with 2 decimal places using period separator (e.g. "4.00 m").
    static func meters(_ meters: Double, locale: Locale = Locale(identifier: "en_US")) -> String {
        let f = NumberFormatter(); f.locale = locale; f.minimumFractionDigits = 2; f.maximumFractionDigits = 2
        return (f.string(from: meters as NSNumber) ?? String(format: "%.2f", meters)) + " m"
    }

    /// Centimeters for backward compatibility (e.g. "400 cm").
    static func centimeters(_ meters: Double, locale: Locale = Locale(identifier: "en_US")) -> String {
        let cm = (meters * 100).rounded()
        let f = NumberFormatter(); f.locale = locale; f.maximumFractionDigits = 0
        return (f.string(from: cm as NSNumber) ?? "\(Int(cm))") + " cm"
    }

    /// Length formatting based on selected unit (mm, m, or both).
    static func length(_ metersValue: Double, unit: MeasurementUnit = .both, locale: Locale = Locale(identifier: "en_US")) -> String {
        switch unit {
        case .millimeters:
            return millimeters(metersValue, locale: locale)
        case .meters:
            return meters(metersValue, locale: locale)
        case .both:
            return "\(millimeters(metersValue, locale: locale)) (\(meters(metersValue, locale: locale)))"
        }
    }

    /// Floor area in m² with 1 decimal place (e.g. "12.0 m²").
    static func squareMeters(_ m2: Double, locale: Locale = Locale(identifier: "en_US")) -> String {
        let f = NumberFormatter(); f.locale = locale; f.minimumFractionDigits = 1; f.maximumFractionDigits = 1
        return (f.string(from: m2 as NSNumber) ?? String(format: "%.1f", m2)) + " m²"
    }

    /// Opening width (top label on dimension line).
    static func openingWidth(_ width: Double, unit: MeasurementUnit = .both, locale: Locale = Locale(identifier: "en_US")) -> String {
        switch unit {
        case .millimeters:
            return millimeters(width, locale: locale)
        case .meters:
            return meters(width, locale: locale)
        case .both:
            let mm = Int((width * 1000).rounded())
            let m = String(format: "%.2f", locale: locale, width)
            return "\(mm) mm (\(m) m)"
        }
    }

    /// Opening height (bottom label under dimension line).
    static func openingHeight(_ height: Double, unit: MeasurementUnit = .both, locale: Locale = Locale(identifier: "en_US")) -> String {
        switch unit {
        case .millimeters:
            return millimeters(height, locale: locale)
        case .meters:
            return meters(height, locale: locale)
        case .both:
            let mm = Int((height * 1000).rounded())
            let m = String(format: "%.2f", locale: locale, height)
            return "\(mm) mm (\(m) m)"
        }
    }

    /// Combined opening dimensions (W / H).
    static func openingDimensions(width: Double, height: Double, unit: MeasurementUnit = .both, locale: Locale = Locale(identifier: "en_US")) -> String {
        "W: \(openingWidth(width, unit: unit, locale: locale)) · H: \(openingHeight(height, unit: unit, locale: locale))"
    }

    /// Parapet / sill height (BRH: Brüstungshöhe / Parapet Height) for windows.
    static func parapetHeight(_ sillHeight: Double, unit: MeasurementUnit = .both, locale: Locale = Locale(identifier: "en_US")) -> String {
        switch unit {
        case .millimeters:
            return "BRH: \(millimeters(sillHeight, locale: locale))"
        case .meters:
            return "BRH: \(meters(sillHeight, locale: locale))"
        case .both:
            let mm = Int((sillHeight * 1000).rounded())
            let m = String(format: "%.2f", locale: locale, sillHeight)
            return "BRH: \(mm) mm (\(m) m)"
        }
    }
}

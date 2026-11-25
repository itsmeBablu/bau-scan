import Foundation

enum ProjectQuantitiesCSV {
    static func data(_ report: ProjectReport, locale: Locale, wastePercent: Double? = nil) -> Data {
        let wastePercent = wastePercent ?? report.wastePercent
        let headers = ["Scan","Room","Floor area (m²)","Net wall area (m²)","Projected ceiling area (m²)","Perimeter (m)","Volume min (m³)","Volume max (m³)","Doors","Windows","Other openings","Flooring incl. waste (m²)","Paint area incl. waste (m²)"]
        func number(_ value: Double) -> String { String(format:"%.3f",locale:locale,value) }
        func cell(_ value: String) -> String {
            let trimmed = value.trimmingCharacters(in:.whitespacesAndNewlines)
            let protected = ["=","+","-","@"].contains(String(trimmed.prefix(1))) ? "'"+value : value
            return "\""+protected.replacingOccurrences(of:"\"",with:"\"\"")+"\""
        }
        var rows = [headers.map { cell(AppLanguage.text($0,locale:locale)) }.joined(separator:";")]
        for scan in report.scans {
            for room in scan.house?.allRooms ?? [] {
                let q = RenovationQuantities(room)
                rows.append(([scan.title,q.name].map(cell)+[q.floorArea,q.wallAreaNet,q.ceilingProjectedArea,q.perimeter,q.volumeMin,q.volumeMax,Double(q.doors),Double(q.windows),Double(q.otherOpenings),q.flooring(wastePercent:wastePercent),q.paintArea(wastePercent:wastePercent)].map { cell(number($0)) }).joined(separator:";"))
            }
        }
        rows.append(cell(AppLanguage.text("Independent surveys may overlap. Ceiling area is projected; volume is a height-based range. Device validation pending.",locale:locale)))
        return Data(("\u{FEFF}"+rows.joined(separator:"\r\n")+"\r\n").utf8)
    }
    static func lines(_ q: RenovationQuantities, locale: Locale, wastePercent: Double = 0) -> [String] {
        func label(_ key: String,_ value: String) -> String { AppLanguage.text(key,locale:locale)+": "+value }
        return [q.name,
                label("Floor area (m²)",MeasurementFormat.squareMeters(q.floorArea,locale:locale)),
                label("Net wall area (m²)",MeasurementFormat.squareMeters(q.wallAreaNet,locale:locale)),
                label("Projected ceiling area (m²)",MeasurementFormat.squareMeters(q.ceilingProjectedArea,locale:locale)),
                label("Perimeter (m)",MeasurementFormat.meters(q.perimeter,locale:locale)),
                label("Volume min–max (m³)",String(format:"%.2f – %.2f",locale:locale,q.volumeMin,q.volumeMax)),
                label("Doors / windows / other openings","\(q.doors) / \(q.windows) / \(q.otherOpenings)"),
                label("Unhosted openings (not subtracted)","\(q.unhostedOpenings)"),
                label("Waste allowance",String(format:"%.0f%%",locale:locale,wastePercent)),
                label("Flooring incl. waste (m²)",MeasurementFormat.squareMeters(q.flooring(wastePercent:wastePercent),locale:locale)),
                label("Paint area incl. waste (m²)",MeasurementFormat.squareMeters(q.paintArea(wastePercent:wastePercent),locale:locale))]
    }
}

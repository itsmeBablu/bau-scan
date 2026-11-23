import Foundation

/// STEP tokens are composed internally. User strings always pass through text().
final class IFCWriter {
    let schema: RevitExportOptions.Schema
    private(set) var entities: [String] = []
    init(schema: RevitExportOptions.Schema) { self.schema = schema }
    @discardableResult func add(_ type: String, _ arguments: String) -> Int {
        entities.append("#\(entities.count + 1)=\(type.uppercased())(\(arguments));")
        return entities.count
    }
    static func ref(_ id: Int) -> String { "#\(id)" }
    static func refs(_ ids: [Int]) -> String { "(" + ids.map(ref).joined(separator: ",") + ")" }
    static func number(_ value: Double) -> String {
        precondition(value.isFinite)
        let string = String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), value == 0 ? 0 : value)
        let trimmed = string.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        return trimmed
    }
    static func text(_ value: String) -> String {
        var result = "'"
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 39: result += "''"
            case 92: result += "\\\\"
            case 32...126: result.unicodeScalars.append(scalar)
            default:
                if scalar.value <= 0xffff { result += String(format: "\\X2\\%04X\\X0\\", scalar.value) }
                else { result += String(format: "\\X4\\%08X\\X0\\", scalar.value) }
            }
        }
        return result + "'"
    }
    /// IFC base-64 encoding of the UUID's 128 bits, most significant first.
    static func compressedGUID(_ uuid: UUID) -> String {
        let bytes = uuid.uuidString.replacingOccurrences(of: "-", with: "")
        var values: [UInt8] = []
        var i = bytes.startIndex
        while i < bytes.endIndex {
            let j = bytes.index(i, offsetBy: 2)
            values.append(UInt8(bytes[i..<j], radix: 16)!)
            i = j
        }
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_$")
        var output = ""
        // Four leading zero bits followed by 128 UUID bits = 22 base-64 digits.
        for digit in 0..<22 {
            var value = 0
            for bit in 0..<6 {
                let index = digit * 6 + bit - 4
                value <<= 1
                if index >= 0 { value |= Int((values[index / 8] >> (7 - index % 8)) & 1) }
            }
            output.append(alphabet[value])
        }
        return output
    }
    /// Stable namespaced IDs for derived segments and relationships.
    static func guid(_ key: String) -> String {
        func hash(_ seed: UInt64) -> UInt64 {
            key.utf8.reduce(seed) { ($0 ^ UInt64($1)) &* 1099511628211 }
        }
        let hex = String(format: "%016llX%016llX", hash(14695981039346656037), hash(7809847782465536322))
        let chars = Array(hex)
        let string = [String(chars[0..<8]),String(chars[8..<12]),String(chars[12..<16]),String(chars[16..<20]),String(chars[20..<32])].joined(separator: "-")
        return text(compressedGUID(UUID(uuidString: string)!))
    }
    func data(timestamp: String) -> Data {
        let view = schema == .ifc4 ? "ViewDefinition [ReferenceView_V1.2]" : "ViewDefinition [CoordinationView_V2.0]"
        let header = """
        ISO-10303-21;
        HEADER;
        FILE_DESCRIPTION((\(Self.text(view))),'2;1');
        FILE_NAME('survey.ifc',\(Self.text(timestamp)),(''),(''),'dWalkScan','dWalkScan','');
        FILE_SCHEMA((\(Self.text(schema.rawValue))));
        ENDSEC;
        DATA;
        """
        return Data((header + "\n" + entities.joined(separator: "\n") + "\nENDSEC;\nEND-ISO-10303-21;\n").utf8)
    }
}

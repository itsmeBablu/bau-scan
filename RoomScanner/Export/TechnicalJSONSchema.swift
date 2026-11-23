import Foundation
import CoreFoundation

/// Validates the keyword subset used by the bundled v1 schema.
/// This is intentionally not a general JSON Schema implementation.
enum TechnicalJSONSchema {
    struct ValidationError: Error { let path: String; let reason: String }
    private final class ResourceToken: NSObject {}

    static func schemaData(resourceName: String = "technical-room-v1.schema") throws -> Data {
        let bundles = [Bundle.main, Bundle(for: ResourceToken.self)]
        guard let url = bundles.compactMap({ $0.url(forResource: resourceName, withExtension: "json") }).first else {
            throw ValidationError(path: "$", reason: "Missing bundled schema")
        }
        return try Data(contentsOf: url)
    }

    static func validate(_ data: Data) throws {
        let schema = try JSONSerialization.jsonObject(with: schemaData()) as! [String: Any]
        try validateNode(JSONSerialization.jsonObject(with: data), schema: schema, root: schema, path: "$")
    }

    /// The handoff has its own version. Validate its extensions and its unchanged v1 core.
    static func validateHandoff(_ data: Data) throws {
        let schema = try JSONSerialization.jsonObject(with: schemaData(resourceName: "technical-survey-handoff-v1.schema")) as! [String: Any]
        let value = try JSONSerialization.jsonObject(with: data)
        try validateNode(value, schema: schema, root: schema, path: "$")
        guard let object = value as? [String: Any] else {
            throw ValidationError(path: "$", reason: "Expected survey object")
        }
        let coreSchema = try JSONSerialization.jsonObject(with: schemaData()) as! [String: Any]
        let keys = Set((coreSchema["properties"] as? [String: Any] ?? [:]).keys)
        let core = object.filter { keys.contains($0.key) }
        try validate(JSONSerialization.data(withJSONObject: core))
        // Decoding checks the Codable structure of route edits, measurements and connections.
        let decoder = JSONDecoder()
        func decode<T: Decodable>(_ type: T.Type, key: String) throws {
            guard let item = object[key] else { return }
            _ = try decoder.decode(type, from: JSONSerialization.data(withJSONObject: item))
        }
        try decode([TechnicalDuctRun].self, key: "ducts")
        try decode([TechnicalPipeConnection].self, key: "connections")
        try decode([TechnicalPointMeasurement].self, key: "measurements")
        try decode(TechnicalScaleCalibration.self, key: "calibration")
        try decode(TechnicalTransform.self, key: "sessionToRoom")
        try decode([TechnicalPipeRun].self, key: "originalPipeRuns")
        try decode([TechnicalMEPSuggestion].self, key: "acceptedDetectionsInSessionCoordinates")
    }

    private static func validateNode(_ value: Any, schema: [String: Any], root: [String: Any], path: String) throws {
        func fail(_ reason: String) throws { throw ValidationError(path: path, reason: reason) }
        if let reference = schema["$ref"] as? String {
            let name = String(reference.dropFirst("#/$defs/".count))
            guard let definitions = root["$defs"] as? [String: Any], let target = definitions[name] as? [String: Any] else {
                try fail("Unknown reference"); return
            }
            try validateNode(value, schema: target, root: root, path: path)
            return
        }
        if let constant = schema["const"], !equal(value, constant) { try fail("Incorrect constant") }
        if let allowed = schema["enum"] as? [Any], !allowed.contains(where: { equal(value, $0) }) { try fail("Invalid enumeration") }
        let types = schema["type"] as? [String] ?? (schema["type"] as? String).map { [$0] } ?? []
        if !types.isEmpty && !types.contains(where: { matches(value, type: $0) }) { try fail("Incorrect type") }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let n = number.doubleValue
            if !n.isFinite { try fail("Nonfinite number") }
            if let minimum = schema["minimum"] as? Double, n < minimum { try fail("Below minimum") }
            if let minimum = schema["exclusiveMinimum"] as? Double, n <= minimum { try fail("Below exclusive minimum") }
        }
        if let string = value as? String {
            if let minimum = schema["minLength"] as? Int, string.count < minimum { try fail("String too short") }
            if schema["format"] as? String == "uuid", UUID(uuidString: string) == nil { try fail("Invalid UUID") }
        }
        if let array = value as? [Any] {
            if let minimum = schema["minItems"] as? Int, array.count < minimum { try fail("Too few items") }
            if let itemSchema = schema["items"] as? [String: Any] {
                for (index, item) in array.enumerated() {
                    try validateNode(item, schema: itemSchema, root: root, path: "\(path)[\(index)]")
                }
            }
        }
        if let object = value as? [String: Any] {
            for key in schema["required"] as? [String] ?? [] where object[key] == nil { try fail("Missing \(key)") }
            let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
            for (key, item) in object {
                if let child = properties[key] {
                    try validateNode(item, schema: child, root: root, path: path + "." + key)
                } else if let child = schema["additionalProperties"] as? [String: Any] {
                    try validateNode(item, schema: child, root: root, path: path + "." + key)
                } else if schema["additionalProperties"] as? Bool == false {
                    try fail("Unknown property \(key)")
                }
            }
        }
    }

    private static func equal(_ a: Any, _ b: Any) -> Bool {
        (a as? NSObject)?.isEqual(b) ?? false
    }

    private static func matches(_ value: Any, type: String) -> Bool {
        switch type {
        case "null": return value is NSNull
        case "object": return value is [String: Any]
        case "array": return value is [Any]
        case "string": return value is String
        case "number": return (value as? NSNumber).map { CFGetTypeID($0) != CFBooleanGetTypeID() } ?? false
        default: return false
        }
    }
}

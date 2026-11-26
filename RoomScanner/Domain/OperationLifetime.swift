import Foundation

/// Transient operation ownership, never persisted. A timeout is a warning, not
/// cancellation or permission for another writer to start over the first one.
struct OperationLifetime: Equatable {
    private(set) var id: UUID?
    private(set) var exceededExpectedDuration = false
    var isRunning: Bool { id != nil }

    mutating func begin() -> UUID? {
        guard id == nil else { return nil }
        let value = UUID(); id = value; exceededExpectedDuration = false
        return value
    }
    @discardableResult mutating func warnIfRunning(_ expected: UUID) -> Bool {
        guard id == expected, !exceededExpectedDuration else { return false }
        exceededExpectedDuration = true; return true
    }
    @discardableResult mutating func finish(_ expected: UUID) -> Bool {
        guard id == expected else { return false }
        id = nil; exceededExpectedDuration = false; return true
    }
}

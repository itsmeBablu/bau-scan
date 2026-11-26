/// SwiftUI may reinitialize value views while retaining their State. A cheap
/// holder prevents those discarded initializers from constructing native cameras.
@MainActor final class LazyCaptureResource<Value> {
    private enum Storage { case pending(()->Value), ready(Value) }
    private var storage:Storage
    init(_ factory:@escaping ()->Value) { storage = .pending(factory) }
    var value:Value {
        switch storage {
        case .ready(let value): return value
        case .pending(let factory):
            let value = factory(); storage = .ready(value); return value
        }
    }
}

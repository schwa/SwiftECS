/// An opaque description of how a system input resolves to a value. Produced by ``SystemInput`` conformances.
public struct SystemBinding<Value> {
    internal let access: SystemAccess
    internal let validate: () throws -> Void
    internal let resolve: (SystemScope) -> Value
}

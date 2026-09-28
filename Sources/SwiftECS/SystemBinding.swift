public struct SystemBinding<Value> {
    internal let access: SystemAccess
    internal let validate: () throws -> Void
    internal let resolve: (SystemScope) -> Value
}

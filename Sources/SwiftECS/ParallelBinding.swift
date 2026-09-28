public struct ParallelBinding<Value> {
    internal let binding: SystemBinding<Value>
    internal let prepare: (World) -> (@Sendable (SystemScope) -> Value)
}

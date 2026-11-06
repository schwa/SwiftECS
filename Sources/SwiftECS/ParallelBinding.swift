/// An opaque description of how a parallel system input resolves on worker tasks.
public struct ParallelBinding<Value> {
    internal let binding: SystemBinding<Value>
    internal let prepare: (World) -> (@Sendable (SystemScope) -> Value)
}

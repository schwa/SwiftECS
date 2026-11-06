/// An opaque description of a command input that parallel systems can use.
public struct ParallelCommandBinding<Value> {
    internal let binding: ParallelBinding<Value>
}

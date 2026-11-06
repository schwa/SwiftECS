/// A system input that can be resolved on worker tasks.
public protocol ParallelSystemInput: SystemInput, SendableMetatype {
    /// The binding for use on worker tasks.
    var parallelBinding: ParallelBinding<Value> { get }
}

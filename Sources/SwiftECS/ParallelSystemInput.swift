public protocol ParallelSystemInput: SystemInput, SendableMetatype {
    var parallelBinding: ParallelBinding<Value> { get }
}

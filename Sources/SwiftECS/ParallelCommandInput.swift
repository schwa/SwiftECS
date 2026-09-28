public protocol ParallelCommandInput: ParallelSystemInput {
    var parallelCommands: ParallelCommandBinding<Value> { get }
}

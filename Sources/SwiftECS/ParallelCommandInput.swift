/// A command input that parallel systems can use. Commands from worker tasks merge in schedule order.
public protocol ParallelCommandInput: ParallelSystemInput {
    /// The binding for use on worker tasks.
    var parallelCommands: ParallelCommandBinding<Value> { get }
}

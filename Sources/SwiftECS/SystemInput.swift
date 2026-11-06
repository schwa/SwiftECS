/// A value that a system declares as an input, such as a query or a command buffer.
///
/// The binding records the input's access so the scheduler can detect conflicts and merge commands.
public protocol SystemInput {
    /// The value the system callback receives for this input.
    associatedtype Value
    /// The binding that validates and resolves this input.
    var binding: SystemBinding<Value> { get }
}

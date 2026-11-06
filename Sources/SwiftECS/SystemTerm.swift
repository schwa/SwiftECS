/// A component term in a system query, such as ``Read`` or ``Write``.
public protocol SystemTerm {
    /// The component type the term matches.
    associatedtype ComponentValue: Component
    /// The value the term supplies for each matching row.
    associatedtype Output
    /// The term's binding.
    var definition: SystemTermDefinition<ComponentValue, Output> { get }
}

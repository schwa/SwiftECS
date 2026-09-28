public protocol SystemTerm {
    associatedtype ComponentValue: Component
    associatedtype Output
    var definition: SystemTermDefinition<ComponentValue, Output> { get }
}

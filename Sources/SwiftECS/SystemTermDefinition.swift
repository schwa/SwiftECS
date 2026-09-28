public struct SystemTermDefinition<Value: Component, Output> {
    internal let writes: Bool
    internal let resolve: (SystemComponent<Value>) -> Output
}

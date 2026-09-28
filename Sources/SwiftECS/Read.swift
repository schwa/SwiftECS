public struct Read<Value: Component>: SystemTerm {
    public init() {}

    public var definition: SystemTermDefinition<Value, Value> {
        SystemTermDefinition(writes: false) { $0.value }
    }
}

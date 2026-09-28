public struct Write<Value: Component>: SystemTerm {
    public init() {}

    public var definition: SystemTermDefinition<Value, SystemComponent<Value>> {
        SystemTermDefinition(writes: true) { $0 }
    }
}

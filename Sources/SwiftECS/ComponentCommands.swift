public struct ComponentCommands<Value: Component> {
    internal let scope: SystemScope

    public func set(_ value: Value, on id: EntityID) throws {
        try SystemCommands(scope: scope).set(value, on: id)
    }

    public func remove(from id: EntityID) {
        SystemCommands(scope: scope).remove(Value.self, from: id)
    }
}

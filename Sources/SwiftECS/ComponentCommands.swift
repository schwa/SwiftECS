public struct ComponentCommands<Value: Component> {
    internal let scope: SystemScope
    internal var parallelSet: ((Value, EntityID) throws -> Void)?
    internal var parallelRemove: ((EntityID) -> Void)?

    public func set(_ value: Value, on id: EntityID) throws {
        scope.checkActive()
        if let parallelSet {
            try parallelSet(value, id)
        } else {
            try SystemCommands(scope: scope).set(value, on: id)
        }
    }

    public func remove(from id: EntityID) {
        scope.checkActive()
        if let parallelRemove {
            parallelRemove(id)
        } else {
            SystemCommands(scope: scope).remove(Value.self, from: id)
        }
    }
}

/// Deferred set and remove commands for one component type. Supplied by ``EditComponent``.
public struct ComponentCommands<Value: Component> {
    internal let scope: SystemScope
    internal var parallelSet: ((Value, EntityID) throws -> Void)?
    internal var parallelRemove: ((EntityID) -> Void)?

    /// Sets the component on an entity when commands merge.
    ///
    /// - Throws: ``SystemError/missingCommandEntity(_:)`` during the merge if the entity no longer exists.
    public func set(_ value: Value, on id: EntityID) throws {
        scope.checkActive()
        if let parallelSet {
            try parallelSet(value, id)
        } else {
            try SystemCommands(scope: scope).set(value, on: id)
        }
    }

    /// Removes the component from an entity when commands merge. Does nothing if it is absent.
    public func remove(from id: EntityID) {
        scope.checkActive()
        if let parallelRemove {
            parallelRemove(id)
        } else {
            SystemCommands(scope: scope).remove(Value.self, from: id)
        }
    }
}

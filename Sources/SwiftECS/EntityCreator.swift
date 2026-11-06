/// Creates entities with a fixed set of component types. Supplied by ``CreateEntities``.
public struct EntityCreator<each Value: Component> {
    internal let scope: SystemScope
    internal var parallelCreate: ((repeat each Value) throws -> EntityID)?

    /// Reserves an ID and creates the entity when commands merge.
    ///
    /// The new entity does not appear in the current callback's queries.
    ///
    /// - Returns: The new entity's ID, usable as a target in later commands.
    @discardableResult
    public func create(_ components: repeat each Value) throws -> EntityID {
        scope.checkActive()
        if let parallelCreate {
            return try parallelCreate(repeat each components)
        }
        return try SystemCommands(scope: scope).create(repeat each components)
    }
}

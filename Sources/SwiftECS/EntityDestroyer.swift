/// Destroys entities when commands merge. Supplied by ``DestroyEntities``.
public struct EntityDestroyer {
    internal let scope: SystemScope

    /// Destroys the entity when commands merge. Does nothing if it no longer exists.
    public func destroy(_ id: EntityID) {
        scope.checkActive()
        if let state = scope.parallel {
            state.enqueue { world in world.removeEntity(id) }
        } else {
            SystemCommands(scope: scope).destroy(id)
        }
    }
}

public struct EntityDestroyer {
    internal let scope: SystemScope

    public func destroy(_ id: EntityID) {
        scope.checkActive()
        if let state = scope.parallel {
            state.enqueue { world in world.removeEntity(id) }
        } else {
            SystemCommands(scope: scope).destroy(id)
        }
    }
}

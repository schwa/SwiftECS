public struct EntityDestroyer {
    internal let scope: SystemScope

    public func destroy(_ id: EntityID) {
        SystemCommands(scope: scope).destroy(id)
    }
}

public struct EntityCreator<each Value: Component> {
    internal let scope: SystemScope
    internal var parallelCreate: ((repeat each Value) throws -> EntityID)?

    @discardableResult
    public func create(_ components: repeat each Value) throws -> EntityID {
        scope.checkActive()
        if let parallelCreate {
            return try parallelCreate(repeat each components)
        }
        return try SystemCommands(scope: scope).create(repeat each components)
    }
}

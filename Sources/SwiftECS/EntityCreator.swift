public struct EntityCreator<each Value: Component> {
    internal let scope: SystemScope

    @discardableResult
    public func create(_ components: repeat each Value) throws -> EntityID {
        try SystemCommands(scope: scope).create(repeat each components)
    }
}

public struct SystemOutputRow<each Output> {
    public let entityID: EntityID
    public let fields: (repeat each Output)

    @inlinable
    internal init(entityID: EntityID, fields: repeat each Output) {
        self.entityID = entityID
        self.fields = (repeat each fields)
    }
}

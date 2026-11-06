/// One row of a system query.
public struct SystemOutputRow<each Output> {
    /// The matching entity.
    public let entityID: EntityID
    /// The term outputs, in term order. A query with one term has a single value instead of a tuple.
    public let fields: (repeat each Output)

    @inlinable
    internal init(entityID: EntityID, fields: repeat each Output) {
        self.entityID = entityID
        self.fields = (repeat each fields)
    }
}

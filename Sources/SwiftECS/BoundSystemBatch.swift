@usableFromInline
internal final class BoundSystemBatch<each Output> {
    @usableFromInline let ids: [EntityID]
    @usableFromInline let indices: [Int]?
    @usableFromInline let fields: (repeat (EntityID, Int) -> each Output)
    @usableFromInline let dense: Bool

    @usableFromInline
    init(ids: [EntityID], indices: [Int]?, fields: (repeat (EntityID, Int) -> each Output), dense: Bool) {
        self.ids = ids
        self.indices = indices
        self.fields = (repeat each fields)
        self.dense = dense
    }
}

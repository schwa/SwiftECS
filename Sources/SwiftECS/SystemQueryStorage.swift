@usableFromInline
internal struct SystemQueryStorage<each Value: Component> {
    @usableFromInline let ids: [EntityID]
    @usableFromInline let columns: (repeat Column<each Value>)
    @usableFromInline let matchingIndices: [Int]?
    @usableFromInline let buffers: (repeat TaskColumn<each Value>?)
    @usableFromInline let usesDenseIndices: Bool

    init(ids: [EntityID], columns: (repeat Column<each Value>), matchingIndices: [Int]?, buffers: (repeat TaskColumn<each Value>), usesDenseIndices: Bool) {
        self.ids = ids
        self.columns = (repeat each columns)
        self.matchingIndices = matchingIndices
        self.buffers = (repeat Optional(each buffers))
        self.usesDenseIndices = usesDenseIndices
    }

    @inlinable var count: Int { matchingIndices?.count ?? ids.count }

    init(archetype: Archetype, filter: QueryPredicate?, world: World) {
        buffers = (repeat Optional<TaskColumn<each Value>>.none)
        usesDenseIndices = false
        ids = archetype.entities
        let storage = TypedQueryStorage<repeat each Value>(archetype: archetype)
        columns = (repeat each storage.columns)
        if let filter {
            matchingIndices = archetype.entities.indices.filter {
                world.queries.matches(filter, entityID: archetype.entities[$0], in: world)
            }
        } else {
            matchingIndices = nil
        }
    }
}

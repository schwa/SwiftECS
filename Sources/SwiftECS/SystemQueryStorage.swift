internal struct SystemQueryStorage<each Value: Component> {
    let ids: [EntityID]
    let columns: (repeat Column<each Value>)
    let matchingIndices: [Int]?

    init(archetype: Archetype, filter: QueryPredicate?, world: World) {
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

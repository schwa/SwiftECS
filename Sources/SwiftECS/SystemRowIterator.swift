public struct SystemRowIterator<each Term: SystemTerm>: IteratorProtocol {
    internal let terms: (repeat each Term)
    internal let storage: [SystemQueryStorage<repeat (each Term).ComponentValue>]
    internal let scope: SystemScope
    internal let revision: UInt64
    internal var archetypeIndex = 0
    internal var entityIndex = 0

    public mutating func next() -> SystemRow<repeat each Term>? {
        scope.checkActive()
        while archetypeIndex < storage.count {
            let batch = storage[archetypeIndex]
            guard entityIndex < (batch.matchingIndices?.count ?? batch.ids.count) else {
                archetypeIndex += 1
                entityIndex = 0
                continue
            }
            let index = batch.matchingIndices?[entityIndex] ?? entityIndex
            let id = batch.ids[index]
            entityIndex += 1
            if scope.world.structuralRevision != revision {
                var matches = scope.world.entityExists(id)
                for type in repeat (each Term).ComponentValue.self {
                    matches = matches && scope.world.hasComponent(type, for: id)
                }
                guard matches else {
                    continue
                }
            }
            return SystemRow(entityID: id, fields: (repeat (each terms).definition.resolve(component(id: id, column: each batch.columns, index: index))))
        }
        return nil
    }

    private func component<Value: Component>(id: EntityID, column: Column<Value>, index: Int) -> SystemComponent<Value> {
        let reference = ComponentRef(world: scope.world, entityID: id, column: column, index: index)
        return SystemComponent(entityID: id, scope: scope, reference: reference, revision: revision)
    }
}

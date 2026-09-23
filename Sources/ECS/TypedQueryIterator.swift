public struct TypedQueryIterator<each Value: Component>: IteratorProtocol {
    @usableFromInline internal let world: World
    @usableFromInline internal let storage: [TypedQueryStorage<repeat each Value>]
    @usableFromInline internal var archetypeIndex = 0
    @usableFromInline internal var entityIndex = 0

    internal init(world: World, storage: [TypedQueryStorage<repeat each Value>]) {
        self.world = world
        self.storage = storage
    }

    @inlinable
    public mutating func next() -> TypedEntityRef<repeat each Value>? {
        world.trackStorageAccess()
        while archetypeIndex < storage.count {
            let batch = storage[archetypeIndex]
            if entityIndex < batch.archetype.entities.count {
                let entityID = batch.archetype.entities[entityIndex]
                let reference = TypedEntityRef(world: world, entityID: entityID, index: entityIndex, storage: batch)
                entityIndex += 1
                return reference
            }
            archetypeIndex += 1
            entityIndex = 0
        }
        return nil
    }
}

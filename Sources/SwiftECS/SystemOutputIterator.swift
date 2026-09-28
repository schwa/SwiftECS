public struct SystemOutputIterator<each Output>: IteratorProtocol {
    @usableFromInline internal let storage: [BoundSystemBatch<repeat each Output>]
    @usableFromInline internal let scope: SystemScope
    @usableFromInline internal let revision: UInt64
    @usableFromInline internal let required: Set<ComponentType>
    @usableFromInline internal var archetypeIndex = 0
    @usableFromInline internal var entityIndex = 0

    @usableFromInline
    internal init(storage: [BoundSystemBatch<repeat each Output>], scope: SystemScope, revision: UInt64, required: Set<ComponentType>) {
        self.storage = storage
        self.scope = scope
        self.revision = revision
        self.required = required
    }

    @inlinable
    public mutating func next() -> SystemOutputRow<repeat each Output>? {
        scope.checkActive()
        while archetypeIndex < storage.count {
            let batch = storage[archetypeIndex]
            guard entityIndex < (batch.indices?.count ?? batch.ids.count) else {
                archetypeIndex += 1
                entityIndex = 0
                continue
            }
            let index = batch.indices?[entityIndex] ?? entityIndex
            let id = batch.ids[index]
            let local = batch.dense ? entityIndex : index
            entityIndex += 1
            if !scope.isParallel, scope.world.structuralRevision != revision, !scope.world.matchesSystemRow(id, requiring: required) {
                continue
            }
            return SystemOutputRow(entityID: id, fields: repeat (each batch.fields)(id, local))
        }
        return nil
    }
}

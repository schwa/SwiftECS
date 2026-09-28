internal final class ParallelIDPool: Sendable {
    private let reserved: LockedState<Set<EntityID>>

    init(existing: Set<EntityID>) {
        reserved = LockedState(existing)
    }

    func include(_ ids: Set<EntityID>) {
        reserved.withLock { $0.formUnion(ids) }
    }

    func reserve() -> EntityID {
        reserved.withLock { ids in
            var id = EntityID()
            while !ids.insert(id).inserted {
                id = EntityID()
            }
            return id
        }
    }
}

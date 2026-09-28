extension SystemQuery: ParallelSystemInput where repeat each Term: ParallelSystemTerm {
    public var parallelBinding: ParallelBinding<SystemRows<repeat each Term>> {
        ParallelBinding(binding: binding) { world in
            let prepared = prepareParallel(in: world)
            return { scope in prepared.rows(scope: scope, range: nil) }
        }
    }

    internal func prepareParallel(in world: World) -> PreparedParallelQuery<repeat each Term> {
        world.trackStorageAccess()
        var types: Set<ComponentType> = []
        for type in repeat (each Term).ComponentValue.self {
            types.insert(ComponentType(type))
        }
        let selection = world.queries.prepare(filter, requiring: types, in: world)
        let storage = selection.archetypes.map {
            ParallelQueryStorage(storage: SystemQueryStorage<repeat (each Term).ComponentValue>(archetype: $0, filter: selection.filter, world: world))
        }
        return PreparedParallelQuery<repeat each Term>(terms: (repeat each terms), storage: storage)
    }
}

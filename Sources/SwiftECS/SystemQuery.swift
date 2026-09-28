public struct SystemQuery<each Term: SystemTerm>: SystemInput {
    @usableFromInline internal let terms: (repeat each Term)
    @usableFromInline internal let filter: Query

    public init(_ terms: repeat each Term, matching filter: Query = .all) {
        self.terms = (repeat each terms)
        self.filter = filter
    }

    @inlinable
    public var binding: SystemBinding<SystemRows<repeat each Term>> {
        makeBinding { scope, storage in
            Self.bindRows(terms: (repeat each terms), storage: storage, scope: scope, revision: scope.world.structuralRevision)
        }
    }

    @usableFromInline
    internal func makeBinding(_ bind: @escaping (SystemScope, [SystemQueryStorage<repeat (each Term).ComponentValue>]) -> SystemRows<repeat each Term>) -> SystemBinding<SystemRows<repeat each Term>> {
        var access = SystemAccess()
        repeat Self.record(each terms, in: &access)
        let matching = Query(with: repeat (each Term).ComponentValue.self).and(filter)
        access.queries.insert(QueryDependencies(query: matching))
        return SystemBinding(access: access, validate: {
            var types: Set<ComponentType> = []
            for type in repeat (each Term).ComponentValue.self {
                let component = ComponentType(type)
                guard !(type is AnyObject.Type) else {
                    throw SystemError.referenceComponent(component)
                }
                guard types.insert(component).inserted else {
                    throw SystemError.duplicateTerm(component)
                }
            }
        }, resolve: { scope in
            scope.world.trackStorageAccess()
            var types: Set<ComponentType> = []
            for type in repeat (each Term).ComponentValue.self {
                types.insert(ComponentType(type))
            }
            let selection = scope.world.queries.prepare(filter, requiring: types, in: scope.world)
            let storage = selection.archetypes.map {
                SystemQueryStorage<repeat (each Term).ComponentValue>(archetype: $0, filter: selection.filter, world: scope.world)
            }
            return bind(scope, storage)
        })
    }

    @inlinable
    internal static func bindRows(terms: (repeat each Term), storage: [SystemQueryStorage<repeat (each Term).ComponentValue>], scope: SystemScope, revision: UInt64) -> SystemRows<repeat each Term> {
        let definitions = (repeat (each terms).definition)
        var required: Set<ComponentType> = []
        for type in repeat (each Term).ComponentValue.self {
            required.insert(ComponentType(type))
        }
        let batches = storage.map { batch in
            BoundSystemBatch(ids: batch.ids, indices: batch.matchingIndices, fields: (repeat (each definitions).bind(scope, each batch.columns, each batch.buffers, revision)), dense: batch.usesDenseIndices)
        }
        return SystemOutputRows(storage: batches, scope: scope, revision: revision, required: required)
    }

    private static func record<Field: SystemTerm>(_ term: Field, in access: inout SystemAccess) {
        let type = ComponentType(Field.ComponentValue.self)
        access.reads.insert(type)
        if term.definition.writes {
            access.writes.insert(type)
        }
    }
}

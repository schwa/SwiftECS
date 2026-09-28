public struct SystemQuery<each Term: SystemTerm>: SystemInput {
    internal let terms: (repeat each Term)
    internal let filter: Query

    public init(_ terms: repeat each Term, matching filter: Query = .all) {
        self.terms = (repeat each terms)
        self.filter = filter
    }

    public var binding: SystemBinding<SystemRows<repeat each Term>> {
        var access = SystemAccess()
        repeat Self.record(each terms, in: &access)
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
            return SystemRows<repeat each Term>(terms: (repeat each terms), storage: storage, scope: scope, revision: scope.world.structuralRevision)
        })
    }

    private static func record<Field: SystemTerm>(_ term: Field, in access: inout SystemAccess) {
        let type = ComponentType(Field.ComponentValue.self)
        access.reads.insert(type)
        if term.definition.writes {
            access.writes.insert(type)
        }
    }
}

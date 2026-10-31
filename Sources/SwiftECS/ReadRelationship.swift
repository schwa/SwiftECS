public struct ReadRelationship<Link: Relationship>: SystemInput {
    public init() {}

    public var binding: SystemBinding<RelationshipReader<Link>> {
        var access = SystemAccess()
        access.queries.insert(QueryDependencies(query: Query(.related(Link.self))))
        return SystemBinding(access: access, validate: {}, resolve: { scope in
            let world = scope.world
            let type = RelationshipType(Link.self)
            return RelationshipReader(scope: scope, targets: { source in
                world.trackStorageAccess()
                return world.relationshipGraph.targets(type, from: source)
            }, sources: { target in
                world.trackStorageAccess()
                return world.relationshipGraph.sources(type, to: target)
            })
        })
    }
}

extension ReadRelationship: ParallelSystemInput where Link: ConcurrentRelationship {
    public var parallelBinding: ParallelBinding<RelationshipReader<Link>> {
        ParallelBinding(binding: binding) { world in
            world.trackStorageAccess()
            let snapshot = world.relationshipGraph.snapshot(RelationshipType(Link.self))
            let outgoing = snapshot.outgoing
            let incoming = snapshot.incoming
            return { scope in
                RelationshipReader(scope: scope, targets: { outgoing[$0] ?? [] }, sources: { incoming[$0] ?? [] })
            }
        }
    }
}

public struct RelationshipReader<Link: Relationship> {
    internal let scope: SystemScope
    internal let targetsOf: (EntityID) -> [EntityID]
    internal let sourcesOf: (EntityID) -> [EntityID]

    internal init(scope: SystemScope, targets: @escaping (EntityID) -> [EntityID], sources: @escaping (EntityID) -> [EntityID]) {
        self.scope = scope
        targetsOf = targets
        sourcesOf = sources
    }

    public func targets(of source: EntityID) -> [EntityID] {
        scope.checkActive()
        return targetsOf(source)
    }

    public func target(of source: EntityID) -> EntityID? {
        targets(of: source).first
    }

    public func sources(of target: EntityID) -> [EntityID] {
        scope.checkActive()
        return sourcesOf(target)
    }

    public func contains(from source: EntityID, to target: EntityID) -> Bool {
        targets(of: source).contains(target)
    }
}

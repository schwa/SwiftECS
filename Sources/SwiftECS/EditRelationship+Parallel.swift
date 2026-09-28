extension EditRelationship: ParallelSystemInput, ParallelCommandInput where Link: ConcurrentRelationship {
    public var parallelCommands: ParallelCommandBinding<RelationshipCommands<Link>> {
        ParallelCommandBinding(binding: parallelBinding)
    }

    public var parallelBinding: ParallelBinding<RelationshipCommands<Link>> {
        ParallelBinding(binding: binding) { _ in
            { scope in
                guard let state = scope.parallel else {
                    preconditionFailure("Parallel relationship commands require a worker scope")
                }
                return RelationshipCommands(scope: scope, parallelAdd: { source, target in
                    state.enqueue { world in
                        try Entity(id: source, world: world).addRelationship(Link.self, to: Entity(id: target, world: world))
                    }
                }, parallelRemove: { source, target in
                    state.enqueue { world in
                        try Entity(id: source, world: world).removeRelationship(Link.self, to: Entity(id: target, world: world))
                    }
                })
            }
        }
    }
}

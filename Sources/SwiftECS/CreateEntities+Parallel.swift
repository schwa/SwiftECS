extension CreateEntities: ParallelSystemInput, ParallelCommandInput where repeat each Value: ConcurrentComponent {
    public var parallelCommands: ParallelCommandBinding<EntityCreator<repeat each Value>> {
        ParallelCommandBinding(binding: parallelBinding)
    }

    public var parallelBinding: ParallelBinding<EntityCreator<repeat each Value>> {
        ParallelBinding(binding: binding) { _ in
            { scope in
                EntityCreator<repeat each Value>(scope: scope) { (components: repeat each Value) in
                    guard let state = scope.parallel else {
                        preconditionFailure("Parallel creator requires a worker scope")
                    }
                    let id = state.reserve()
                    state.enqueue { world in
                        world.createEntity(id: id, repeat each components)
                    }
                    return id
                }
            }
        }
    }
}

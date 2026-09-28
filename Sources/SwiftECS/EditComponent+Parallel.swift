extension EditComponent: ParallelSystemInput, ParallelCommandInput where Value: ConcurrentComponent {
    public var parallelCommands: ParallelCommandBinding<ComponentCommands<Value>> {
        ParallelCommandBinding(binding: parallelBinding)
    }

    public var parallelBinding: ParallelBinding<ComponentCommands<Value>> {
        ParallelBinding(binding: binding) { _ in
            { scope in
                guard let state = scope.parallel else {
                    preconditionFailure("Parallel component commands require a worker scope")
                }
                return ComponentCommands(scope: scope, parallelSet: { value, id in
                    state.enqueue { world in
                        guard world.entityExists(id) else {
                            throw SystemError.missingCommandEntity(id)
                        }
                        world.addComponent(value, to: id)
                    }
                }, parallelRemove: { id in
                    state.enqueue { world in world.removeComponent(Value.self, from: id) }
                })
            }
        }
    }
}

extension DestroyEntities: ParallelSystemInput, ParallelCommandInput {
    public var parallelCommands: ParallelCommandBinding<EntityDestroyer> {
        ParallelCommandBinding(binding: parallelBinding)
    }

    public var parallelBinding: ParallelBinding<EntityDestroyer> {
        ParallelBinding(binding: binding) { _ in { EntityDestroyer(scope: $0) } }
    }
}

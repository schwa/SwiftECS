/// An input that permits deferred entity destruction.
public struct DestroyEntities: SystemInput {
    /// Creates the input.
    public init() {}

    public var binding: SystemBinding<EntityDestroyer> {
        SystemBinding(access: SystemAccess(commandEffects: CommandEffects(destroysEntities: true)), validate: {}, resolve: { EntityDestroyer(scope: $0) })
    }
}

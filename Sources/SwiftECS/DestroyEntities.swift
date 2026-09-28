public struct DestroyEntities: SystemInput {
    public init() {}

    public var binding: SystemBinding<EntityDestroyer> {
        SystemBinding(access: SystemAccess(commandEffects: CommandEffects(destroysEntities: true)), validate: {}, resolve: { EntityDestroyer(scope: $0) })
    }
}

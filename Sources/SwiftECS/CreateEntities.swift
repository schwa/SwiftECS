/// An input that permits deferred creation of entities with exactly the given component types.
public struct CreateEntities<each Value: Component>: SystemInput {
    /// Creates the input for the given component types.
    public init(_: repeat (each Value).Type) {}

    public var binding: SystemBinding<EntityCreator<repeat each Value>> {
        var signature: Set<ComponentType> = []
        for type in repeat (each Value).self {
            signature.insert(ComponentType(type))
        }
        let effects = CommandEffects(creationSignatures: [signature])
        return SystemBinding(access: SystemAccess(commandEffects: effects), validate: {
            var seen: Set<ComponentType> = []
            for type in repeat (each Value).self {
                guard !(type is AnyObject.Type) else {
                    throw SystemError.referenceComponent(ComponentType(type))
                }
                guard seen.insert(ComponentType(type)).inserted else {
                    throw SystemError.duplicateTerm(ComponentType(type))
                }
            }
        }, resolve: { EntityCreator<repeat each Value>(scope: $0) })
    }
}

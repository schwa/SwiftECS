/// An input that permits deferred sets and removals of one component type.
public struct EditComponent<Value: Component>: SystemInput {
    /// Creates the input.
    public init() {}

    public var binding: SystemBinding<ComponentCommands<Value>> {
        let effects = CommandEffects(components: [ComponentType(Value.self)])
        return SystemBinding(access: SystemAccess(commandEffects: effects), validate: {
            guard !(Value.self is AnyObject.Type) else {
                throw SystemError.referenceComponent(ComponentType(Value.self))
            }
        }, resolve: { ComponentCommands(scope: $0) })
    }
}

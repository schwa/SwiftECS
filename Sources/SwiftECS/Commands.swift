public struct Commands: SystemInput {
    public init() {}

    public var binding: SystemBinding<SystemCommands> {
        SystemBinding(access: SystemAccess(commandEffects: CommandEffects(isUnrestricted: true)), validate: {}, resolve: { SystemCommands(scope: $0) })
    }
}

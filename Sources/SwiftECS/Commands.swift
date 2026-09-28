public struct Commands: SystemInput {
    public init() {}

    public var binding: SystemBinding<SystemCommands> {
        SystemBinding(access: SystemAccess(changesStructure: true), validate: {}, resolve: { SystemCommands(scope: $0) })
    }
}

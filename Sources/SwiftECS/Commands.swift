/// An input that grants unrestricted deferred commands.
///
/// Prefer the narrower inputs (``CreateEntities``, ``EditComponent``, ``EditRelationship``, ``DestroyEntities``).
/// Unrestricted commands force a merge barrier around the system.
public struct Commands: SystemInput {
    /// Creates the input.
    public init() {}

    public var binding: SystemBinding<SystemCommands> {
        SystemBinding(access: SystemAccess(commandEffects: CommandEffects(isUnrestricted: true)), validate: {}, resolve: { SystemCommands(scope: $0) })
    }
}

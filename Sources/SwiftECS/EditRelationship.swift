/// An input that permits deferred edits of one relationship type.
public struct EditRelationship<Link: Relationship>: SystemInput {
    /// Creates the input.
    public init() {}

    public var binding: SystemBinding<RelationshipCommands<Link>> {
        let effects = CommandEffects(relationships: [RelationshipType(Link.self)])
        return SystemBinding(access: SystemAccess(commandEffects: effects), validate: {}, resolve: { RelationshipCommands(scope: $0) })
    }
}

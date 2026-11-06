extension QueryPredicate {
    /// Matches entities with an outgoing link of the given type.
    ///
    /// - Parameters:
    ///   - type: The relationship type.
    ///   - target: The required target, or `nil` to match any target.
    public static func related<R: Relationship>(_ type: R.Type, to target: EntityID? = nil) -> QueryPredicate {
        .relationship(RelationshipType(type), target)
    }

    /// Matches entities that reach the root by following links of the given type. The root does not match.
    public static func descendant<R: Relationship>(of root: EntityID, via type: R.Type) -> QueryPredicate {
        .descendant(RelationshipType(type), root)
    }

    /// Matches the root's children, grandchildren, and so on. The root does not match.
    public static func descendant(of root: EntityID) -> QueryPredicate {
        .descendant(RelationshipType(ChildOf.self), root)
    }
}

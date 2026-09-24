extension QueryPredicate {
    public static func related<R: Relationship>(_ type: R.Type, to target: EntityID? = nil) -> QueryPredicate {
        .relationship(RelationshipType(type), target)
    }

    public static func descendant<R: Relationship>(of root: EntityID, via type: R.Type) -> QueryPredicate {
        .descendant(RelationshipType(type), root)
    }

    public static func descendant(of root: EntityID) -> QueryPredicate {
        .descendant(RelationshipType(ChildOf.self), root)
    }
}

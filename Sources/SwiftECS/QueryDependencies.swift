/// A system query's matching predicate and the types it depends on.
public struct QueryDependencies: Hashable, Sendable {
    /// The complete matching query, including the terms' component types.
    public let query: Query
    /// The component types the predicate mentions.
    public let components: Set<ComponentType>
    /// The relationship types the predicate mentions.
    public let relationships: Set<RelationshipType>

    internal init(query: Query) {
        self.query = query
        var components: Set<ComponentType> = []
        var relationships: Set<RelationshipType> = []
        Self.collect(query.predicate, components: &components, relationships: &relationships)
        self.components = components
        self.relationships = relationships
    }

    internal func canMatch(creationSignature: Set<ComponentType>) -> Bool {
        Self.possibilities(query.predicate, signature: creationSignature).matches
    }

    private static func collect(_ predicate: QueryPredicate, components: inout Set<ComponentType>, relationships: inout Set<RelationshipType>) {
        switch predicate {
        case .contains(let type):
            components.insert(type)
        case .relationship(let type, _), .descendant(let type, _):
            relationships.insert(type)
        case .not(let inner):
            collect(inner, components: &components, relationships: &relationships)
        case .and(let children), .or(let children):
            for child in children {
                collect(child, components: &components, relationships: &relationships)
            }
        case .all, .none:
            break
        }
    }

    private static func possibilities(_ predicate: QueryPredicate, signature: Set<ComponentType>) -> (matches: Bool, misses: Bool) {
        switch predicate {
        case .contains(let type):
            return (signature.contains(type), !signature.contains(type))
        case .relationship, .descendant:
            return (true, true)
        case .not(let inner):
            let result = possibilities(inner, signature: signature)
            return (result.misses, result.matches)
        case .and(let children):
            let results = children.map { possibilities($0, signature: signature) }
            return (results.allSatisfy(\.matches), results.contains(where: \.misses))
        case .or(let children):
            let results = children.map { possibilities($0, signature: signature) }
            return (results.contains(where: \.matches), results.allSatisfy(\.misses))
        case .all:
            return (true, false)
        case .none:
            return (false, true)
        }
    }
}

public struct RelationshipCommands<Link: Relationship> {
    internal let scope: SystemScope

    public func add(from source: EntityID, to target: EntityID) {
        SystemCommands(scope: scope).addRelationship(Link.self, from: source, to: target)
    }

    public func remove(from source: EntityID, to target: EntityID) {
        SystemCommands(scope: scope).removeRelationship(Link.self, from: source, to: target)
    }
}

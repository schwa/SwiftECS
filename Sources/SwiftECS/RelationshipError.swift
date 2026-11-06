/// Errors thrown when editing relationships.
public enum RelationshipError: Error, Equatable {
    /// The two entities belong to different worlds.
    case differentWorlds
    /// The entity no longer exists.
    case missingEntity(EntityID)
    /// The link makes a cycle in an acyclic relationship.
    case cycleDetected(RelationshipType)
}

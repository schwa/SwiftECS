public enum RelationshipError: Error, Equatable {
    case differentWorlds
    case missingEntity(EntityID)
    case cycleDetected(RelationshipType)
}

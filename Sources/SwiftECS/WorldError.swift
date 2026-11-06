/// Errors thrown by world lifecycle operations.
public enum WorldError: Error, Equatable {
    /// The entity handle belongs to a different world.
    case foreignEntity(EntityID)
}

/// A type-erased identifier for a relationship type.
public struct RelationshipType: Hashable, Sendable {
    internal let id: ObjectIdentifier

    /// Creates an identifier for the given relationship type.
    public init<R: Relationship>(_ type: R.Type) {
        id = ObjectIdentifier(type)
    }
}

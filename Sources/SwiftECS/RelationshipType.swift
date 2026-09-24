public struct RelationshipType: Hashable, Sendable {
    internal let id: ObjectIdentifier

    public init<R: Relationship>(_ type: R.Type) {
        id = ObjectIdentifier(type)
    }
}

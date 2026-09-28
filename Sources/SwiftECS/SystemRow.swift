public struct SystemRow<each Term: SystemTerm> {
    public let entityID: EntityID
    public let fields: (repeat (each Term).Output)
}

/// The access a system declares through its inputs.
public struct SystemAccess: Equatable, Sendable {
    /// The component types the system reads. Includes written types.
    public internal(set) var reads: Set<ComponentType> = []
    /// The component types the system writes in place.
    public internal(set) var writes: Set<ComponentType> = []
    /// The structural changes that the system's deferred commands can make.
    public internal(set) var commandEffects = CommandEffects()
    /// The complete matching predicates of the system's queries.
    public internal(set) var queries: Set<QueryDependencies> = []

    /// Whether the system can make deferred structural changes.
    public var changesStructure: Bool { !commandEffects.isEmpty }

    /// Whether the two systems cannot safely run at the same time.
    ///
    /// This reports conflicts only. It does not change execution order.
    public func conflicts(with other: SystemAccess) -> Bool {
        commandEffects.requiresMerge(before: other) || other.commandEffects.requiresMerge(before: self)
            || commandEffects.overlaps(other.commandEffects)
            || !writes.isDisjoint(with: other.reads.union(other.writes))
            || !other.writes.isDisjoint(with: reads)
    }

    internal mutating func merge(_ other: SystemAccess) {
        reads.formUnion(other.reads)
        writes.formUnion(other.writes)
        commandEffects.merge(other.commandEffects)
        queries.formUnion(other.queries)
    }
}

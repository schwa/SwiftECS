public struct SystemAccess: Equatable, Sendable {
    public internal(set) var reads: Set<ComponentType> = []
    public internal(set) var writes: Set<ComponentType> = []
    public internal(set) var commandEffects = CommandEffects()
    public internal(set) var queries: Set<QueryDependencies> = []

    public var changesStructure: Bool { !commandEffects.isEmpty }

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

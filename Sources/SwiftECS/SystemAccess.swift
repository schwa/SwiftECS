public struct SystemAccess: Equatable, Sendable {
    public internal(set) var reads: Set<ComponentType> = []
    public internal(set) var writes: Set<ComponentType> = []
    public internal(set) var changesStructure = false

    public func conflicts(with other: SystemAccess) -> Bool {
        changesStructure || other.changesStructure
            || !writes.isDisjoint(with: other.reads.union(other.writes))
            || !other.writes.isDisjoint(with: reads)
    }

    internal mutating func merge(_ other: SystemAccess) {
        reads.formUnion(other.reads)
        writes.formUnion(other.writes)
        changesStructure = changesStructure || other.changesStructure
    }
}

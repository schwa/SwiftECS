public struct CommandEffects: Equatable, Sendable {
    public internal(set) var creationSignatures: Set<Set<ComponentType>> = []
    public internal(set) var components: Set<ComponentType> = []
    public internal(set) var relationships: Set<RelationshipType> = []
    public internal(set) var destroysEntities = false
    public internal(set) var isUnrestricted = false

    public var isEmpty: Bool {
        creationSignatures.isEmpty && components.isEmpty && relationships.isEmpty && !destroysEntities && !isUnrestricted
    }

    internal var requiresBarrier: Bool {
        destroysEntities || isUnrestricted
    }

    internal func requiresMerge(before access: SystemAccess) -> Bool {
        guard !isEmpty else {
            return false
        }
        if requiresBarrier || access.commandEffects.requiresBarrier {
            return true
        }
        if !components.isDisjoint(with: access.reads.union(access.writes)) {
            return true
        }
        return access.queries.contains { dependency in
            !components.isDisjoint(with: dependency.components)
                || !relationships.isDisjoint(with: dependency.relationships)
                || creationSignatures.contains { dependency.canMatch(creationSignature: $0) }
        }
    }

    internal func overlaps(_ other: CommandEffects) -> Bool {
        guard !isEmpty, !other.isEmpty else {
            return false
        }
        return requiresBarrier || other.requiresBarrier
            || !components.isDisjoint(with: other.components)
            || !relationships.isDisjoint(with: other.relationships)
            || creationSignatures.contains { !$0.isDisjoint(with: other.components) }
            || other.creationSignatures.contains { !$0.isDisjoint(with: components) }
    }

    internal mutating func merge(_ other: CommandEffects) {
        creationSignatures.formUnion(other.creationSignatures)
        components.formUnion(other.components)
        relationships.formUnion(other.relationships)
        destroysEntities = destroysEntities || other.destroysEntities
        isUnrestricted = isUnrestricted || other.isUnrestricted
    }
}

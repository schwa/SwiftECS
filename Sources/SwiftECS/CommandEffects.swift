/// The structural changes a system's deferred commands may make.
public struct CommandEffects: Equatable, Sendable {
    /// The component sets of entities the system may create.
    public internal(set) var creationSignatures: Set<Set<ComponentType>> = []
    /// The component types the system may set or remove.
    public internal(set) var components: Set<ComponentType> = []
    /// The relationship types the system may add or remove.
    public internal(set) var relationships: Set<RelationshipType> = []
    /// Whether the system may destroy entities.
    public internal(set) var destroysEntities = false
    /// Whether the system uses unrestricted ``Commands``.
    public internal(set) var isUnrestricted = false

    /// Whether the system makes no deferred structural changes.
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

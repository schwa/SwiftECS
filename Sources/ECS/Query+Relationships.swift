extension QueryPredicate {
    public static func related<R: Relationship>(_ type: R.Type, to target: EntityID? = nil) -> QueryPredicate {
        .relationship(RelationshipType(type), target)
    }

    public static func descendant<R: Relationship>(of root: EntityID, via type: R.Type) -> QueryPredicate {
        .descendant(RelationshipType(type), root)
    }

    public static func descendant(of root: EntityID) -> QueryPredicate {
        .descendant(RelationshipType(ChildOf.self), root)
    }

    internal var requiresEntityFiltering: Bool {
        switch self {
        case .relationship, .descendant:
            return true
        case let .not(inner):
            return inner.requiresEntityFiltering
        case let .and(predicates), let .or(predicates):
            return predicates.contains(where: \.requiresEntityFiltering)
        case .contains, .all, .none:
            return false
        }
    }

    internal func matches(entityID: EntityID, signature: ArchetypeSignature, world: World) -> Bool {
        switch self {
        case .all:
            return true
        case .none:
            return false
        case let .contains(type):
            return signature.contains(type)
        case let .relationship(type, target):
            return world.relationships[type]?.contains(source: entityID, target: target) == true
        case let .descendant(type, root):
            return entityID != root && world.relationships[type]?.reaches(from: entityID, to: root) == true
        case let .not(inner):
            return !inner.matches(entityID: entityID, signature: signature, world: world)
        case let .and(predicates):
            return predicates.allSatisfy { $0.matches(entityID: entityID, signature: signature, world: world) }
        case let .or(predicates):
            return predicates.contains { $0.matches(entityID: entityID, signature: signature, world: world) }
        }
    }
}

extension Query {
    internal var entityFilter: Query? {
        predicate.requiresEntityFiltering ? self : nil
    }

    @usableFromInline
    internal func matchesEntity(_ entityID: EntityID, in world: World) -> Bool {
        guard let location = world.entityLocations[entityID] else {
            return false
        }
        return predicate.matches(entityID: entityID, signature: location.signature, world: world)
    }
}

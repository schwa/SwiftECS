internal struct QuerySelection {
    let archetypes: [Archetype]
    let filter: QueryPredicate?
}

@usableFromInline
internal final class QueryEngine {
    private struct CacheEntry {
        let generation: UInt64
        let selection: QuerySelection?
    }

    private enum Match {
        case yes, no, requiresEntity

        init(_ matches: Bool) {
            self = matches ? .yes : .no
        }

        var inverted: Match {
            switch self {
            case .yes: .no
            case .no: .yes
            case .requiresEntity: .requiresEntity
            }
        }
    }

    private var generation: UInt64 = 0
    private var registered: [Query: CacheEntry] = [:]

    func register(_ query: Query) {
        if registered[query] == nil {
            registered[query] = CacheEntry(generation: generation, selection: nil)
        }
    }

    func unregister(_ query: Query) {
        registered.removeValue(forKey: query)
    }

    func isRegistered(_ query: Query) -> Bool {
        registered[query] != nil
    }

    func invalidateArchetypes() {
        generation &+= 1
    }

    func prepare(_ query: Query, requiring requiredTypes: Set<ComponentType>, in world: World) -> QuerySelection {
        let selection: QuerySelection
        if let cached = registered[query] {
            if cached.generation == generation, let prepared = cached.selection {
                selection = prepared
            } else {
                selection = select(query.predicate, in: world)
                registered[query] = CacheEntry(generation: generation, selection: selection)
            }
        } else {
            selection = select(query.predicate, in: world)
        }
        guard !requiredTypes.isEmpty else {
            return selection
        }
        return QuerySelection(archetypes: selection.archetypes.filter { requiredTypes.isSubset(of: $0.signature.types) }, filter: selection.filter)
    }

    func snapshot(_ query: Query, in world: World) -> [Entity] {
        let selection = prepare(query, requiring: [], in: world)
        var result: [Entity] = []
        for archetype in selection.archetypes {
            for entityID in archetype.entities {
                if let filter = selection.filter, !matches(filter, entityID: entityID, in: world) {
                    continue
                }
                result.append(Entity(id: entityID, world: world))
            }
        }
        return result
    }

    @usableFromInline
    func matches(_ predicate: QueryPredicate, entityID: EntityID, in world: World) -> Bool {
        guard let location = world.entityLocations[entityID] else {
            return false
        }
        return evaluate(predicate, signature: location.signature, entityID: entityID, in: world) == .yes
    }

    private func select(_ predicate: QueryPredicate, in world: World) -> QuerySelection {
        var archetypes: [Archetype] = []
        var requiresEntity = false
        for archetype in world.archetypes.values {
            let result = evaluate(predicate, signature: archetype.signature, entityID: nil, in: world)
            if result != .no {
                archetypes.append(archetype)
                requiresEntity = requiresEntity || result == .requiresEntity
            }
        }
        return QuerySelection(archetypes: archetypes, filter: requiresEntity ? predicate : nil)
    }

    private func evaluate(_ predicate: QueryPredicate, signature: ArchetypeSignature, entityID: EntityID?, in world: World) -> Match {
        switch predicate {
        case .all:
            return .yes
        case .none:
            return .no
        case let .contains(type):
            return Match(signature.contains(type))
        case let .relationship(type, target):
            guard let entityID else {
                return .requiresEntity
            }
            return Match(world.relationships[type]?.contains(source: entityID, target: target) == true)
        case let .descendant(type, root):
            guard let entityID else {
                return .requiresEntity
            }
            return Match(entityID != root && world.relationships[type]?.reaches(from: entityID, to: root) == true)
        case let .not(inner):
            return evaluate(inner, signature: signature, entityID: entityID, in: world).inverted
        case let .and(predicates):
            return combine(predicates, signature: signature, entityID: entityID, in: world, shortCircuit: .no)
        case let .or(predicates):
            return combine(predicates, signature: signature, entityID: entityID, in: world, shortCircuit: .yes)
        }
    }

    private func combine(_ predicates: [QueryPredicate], signature: ArchetypeSignature, entityID: EntityID?, in world: World, shortCircuit: Match) -> Match {
        var requiresEntity = false
        for predicate in predicates {
            let result = evaluate(predicate, signature: signature, entityID: entityID, in: world)
            if result == shortCircuit {
                return shortCircuit
            }
            requiresEntity = requiresEntity || result == .requiresEntity
        }
        return requiresEntity ? .requiresEntity : shortCircuit.inverted
    }
}

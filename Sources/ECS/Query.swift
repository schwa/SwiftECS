/// A predicate for matching entities based on their components.
public indirect enum QueryPredicate: Hashable, Sendable {
    /// Match entities that contain a specific component type.
    case contains(ComponentType)

    case relationship(RelationshipType, EntityID?)
    case descendant(RelationshipType, EntityID)

    /// Match entities that do NOT match the inner predicate.
    case not(QueryPredicate)

    /// Match entities that match ALL inner predicates.
    case and([QueryPredicate])

    /// Match entities that match ANY inner predicate.
    case or([QueryPredicate])

    /// A predicate that always matches.
    case all

    /// A predicate that never matches.
    case none
}

// MARK: - Predicate Construction

extension QueryPredicate {
    /// Create a predicate that matches entities containing the given component type.
    public static func contains<T: Component>(_ type: T.Type) -> QueryPredicate {
        .contains(ComponentType(type))
    }

    /// Combine predicates with AND.
    public static func && (lhs: QueryPredicate, rhs: QueryPredicate) -> QueryPredicate {
        switch (lhs, rhs) {
        case (.all, let other), (let other, .all):
            return other
        case (.none, _), (_, .none):
            return .none
        case let (.and(left), .and(right)):
            return .and(left + right)
        case let (.and(left), right):
            return .and(left + [right])
        case let (left, .and(right)):
            return .and([left] + right)
        default:
            return .and([lhs, rhs])
        }
    }

    /// Combine predicates with OR.
    public static func || (lhs: QueryPredicate, rhs: QueryPredicate) -> QueryPredicate {
        switch (lhs, rhs) {
        case (.none, let other), (let other, .none):
            return other
        case (.all, _), (_, .all):
            return .all
        case let (.or(left), .or(right)):
            return .or(left + right)
        case let (.or(left), right):
            return .or(left + [right])
        case let (left, .or(right)):
            return .or([left] + right)
        default:
            return .or([lhs, rhs])
        }
    }

    /// Negate a predicate.
    public static prefix func ! (predicate: QueryPredicate) -> QueryPredicate {
        switch predicate {
        case .all:
            return .none
        case .none:
            return .all
        case let .not(inner):
            return inner // Double negation
        default:
            return .not(predicate)
        }
    }
}

// MARK: - Query

/// A query for finding entities in a world.
public struct Query: Hashable, Sendable {
    /// The predicate used to filter entities.
    public let predicate: QueryPredicate

    /// Create a query with the given predicate.
    public init(_ predicate: QueryPredicate) {
        self.predicate = predicate
    }

    // Pack expansions use types; SwiftLint does not recognize the reference.
    // swiftlint:disable unused_parameter
    /// Create a query that matches entities with all the given component types.
    public init<each T: Component>(with types: repeat (each T).Type) {
        var predicates: [QueryPredicate] = []
        repeat predicates.append(.contains(ComponentType((each T).self)))
        self.predicate = predicates.isEmpty ? .all : (predicates.count == 1 ? predicates[0] : .and(predicates))
    }

    // swiftlint:enable unused_parameter

    /// Create a query matching all entities.
    public static var all: Query {
        Query(.all)
    }

    /// Create a query matching no entities.
    public static var none: Query {
        Query(.none)
    }
}

// MARK: - Query Builder Methods

extension Query {
    /// Add a requirement for the given component type.
    public func with<T: Component>(_ type: T.Type) -> Query {
        Query(predicate && .contains(type))
    }

    /// Add an exclusion for the given component type.
    public func without<T: Component>(_ type: T.Type) -> Query {
        Query(predicate && !.contains(type))
    }

    /// Combine with another query using AND.
    public func and(_ other: Query) -> Query {
        Query(predicate && other.predicate)
    }

    /// Combine with another query using OR.
    public func or(_ other: Query) -> Query {
        Query(predicate || other.predicate)
    }

    /// Negate this query.
    public var negated: Query {
        Query(!predicate)
    }
}

// MARK: - Signature Matching

extension QueryPredicate {
    /// Test if a signature matches this predicate.
    func matches(_ signature: ArchetypeSignature) -> Bool {
        signatureMatch(signature) != .no
    }

    private enum SignatureMatch {
        case yes, no, requiresEntity

        var inverted: SignatureMatch {
            switch self {
            case .yes: .no
            case .no: .yes
            case .requiresEntity: .requiresEntity
            }
        }
    }

    private func signatureMatch(_ signature: ArchetypeSignature) -> SignatureMatch {
        switch self {
        case .all:
            return .yes
        case .none:
            return .no
        case let .contains(componentType):
            return signature.contains(componentType) ? .yes : .no
        case .relationship, .descendant:
            return .requiresEntity
        case let .not(inner):
            return inner.signatureMatch(signature).inverted
        case let .and(predicates):
            return combinedMatch(predicates, signature: signature, shortCircuit: .no)
        case let .or(predicates):
            return combinedMatch(predicates, signature: signature, shortCircuit: .yes)
        }
    }

    private func combinedMatch(_ predicates: [QueryPredicate], signature: ArchetypeSignature, shortCircuit: SignatureMatch) -> SignatureMatch {
        var requiresEntity = false
        for predicate in predicates {
            let result = predicate.signatureMatch(signature)
            if result == shortCircuit {
                return shortCircuit
            }
            requiresEntity = requiresEntity || result == .requiresEntity
        }
        return requiresEntity ? .requiresEntity : shortCircuit.inverted
    }
}

extension Query {
    /// Test if a signature matches this query.
    func matches(_ signature: ArchetypeSignature) -> Bool {
        predicate.matches(signature)
    }
}

// MARK: - World Integration

extension World {
    /// Execute a query and return matching entities.
    public func snapshot(matching query: Query) -> [Entity] {
        trackStorageAccess()
        var result: [Entity] = []
        let filter = query.entityFilter
        for archetype in archetypes.values where query.matches(archetype.signature) {
            for entityID in archetype.entities where filter?.matchesEntity(entityID, in: self) != false {
                result.append(Entity(id: entityID, world: self))
            }
        }
        return result
    }

    /// Execute a query with component type requirements.
    public func snapshot<each T: Component>(with types: repeat (each T).Type) -> [Entity] {
        snapshot(matching: Query(with: repeat each types))
    }
}

// MARK: - Registered Query Support

/// Internal storage for registered query cache.
final class RegisteredQueryCache {
    var matchingArchetypes: [ArchetypeSignature] = []
    var isDirty: Bool = true
}

/// A lazy sequence of entities matching a query.
public struct QuerySequence: Sequence {
    let world: World
    let archetypes: [Archetype]
    let filter: Query?

    public func makeIterator() -> QueryIterator {
        world.trackStorageAccess()
        return QueryIterator(world: world, archetypes: archetypes, filter: filter)
    }
}

/// Iterator for QuerySequence.
public struct QueryIterator: IteratorProtocol {
    let world: World
    let archetypes: [Archetype]
    let filter: Query?
    var archetypeIndex: Int = 0
    var entityIndex: Int = 0

    public mutating func next() -> Entity? {
        world.trackStorageAccess()
        while archetypeIndex < archetypes.count {
            let archetype = archetypes[archetypeIndex]
            if entityIndex < archetype.entities.count {
                let entity = Entity(id: archetype.entities[entityIndex], world: world)
                entityIndex += 1
                if filter?.matchesEntity(entity.id, in: world) == false {
                    continue
                }
                return entity
            }
            archetypeIndex += 1
            entityIndex = 0
        }
        return nil
    }
}

extension World {
    /// Register a query for fast repeated iteration.
    /// The world caches which archetypes match, avoiding predicate evaluation on each query.
    public func register(_ query: Query) {
        if registeredQueries[query] == nil {
            registeredQueries[query] = RegisteredQueryCache()
        }
    }

    /// Unregister a previously registered query.
    public func unregister(_ query: Query) {
        registeredQueries.removeValue(forKey: query)
    }

    /// Check if a query is registered.
    public func isRegistered(_ query: Query) -> Bool {
        registeredQueries[query] != nil
    }

    /// Returns a lazy sequence of entities matching the query.
    /// If the query is registered, uses cached archetype matching for better performance.
    public func entities(matching query: Query) -> QuerySequence {
        QuerySequence(world: self, archetypes: matchingArchetypes(for: query), filter: query.entityFilter)
    }

    /// Get matching archetypes for a query, using cache if registered.
    internal func matchingArchetypes(for query: Query) -> [Archetype] {
        trackStorageAccess()
        if let cache = registeredQueries[query] {
            // Use cached archetype signatures
            if cache.isDirty {
                cache.matchingArchetypes = archetypes.keys.filter { query.matches($0) }
                cache.isDirty = false
            }
            return cache.matchingArchetypes.compactMap { archetypes[$0] }
        }
        // No cache, filter directly
        return archetypes.values.filter { query.matches($0.signature) }
    }
}

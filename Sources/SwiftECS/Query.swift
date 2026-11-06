/// A predicate for matching entities based on their components.
public indirect enum QueryPredicate: Hashable, Sendable {
    /// Match entities that contain a specific component type.
    case contains(ComponentType)

    /// Match entities with an outgoing link of the given type, to the given target or to any target if `nil`.
    case relationship(RelationshipType, EntityID?)
    /// Match entities that reach the given root by following links of the given type.
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
            return inner
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

// MARK: - World Integration

extension World {
    /// Execute a query and return matching entities.
    public func snapshot(matching query: Query) -> [Entity] {
        trackStorageAccess()
        return queries.snapshot(query, in: self)
    }

    /// Execute a query with component type requirements.
    public func snapshot<each T: Component>(with types: repeat (each T).Type) -> [Entity] {
        snapshot(matching: Query(with: repeat each types))
    }
}

// MARK: - Registered Query Support

/// A lazy sequence of entities matching a query.
public struct QuerySequence: Sequence {
    let world: World
    let archetypes: [Archetype]
    let filter: QueryPredicate?

    public func makeIterator() -> QueryIterator {
        world.trackStorageAccess()
        return QueryIterator(world: world, archetypes: archetypes, filter: filter)
    }
}

/// Iterator for QuerySequence.
public struct QueryIterator: IteratorProtocol {
    let world: World
    let archetypes: [Archetype]
    let filter: QueryPredicate?
    var archetypeIndex: Int = 0
    var entityIndex: Int = 0

    public mutating func next() -> Entity? {
        world.trackStorageAccess()
        while archetypeIndex < archetypes.count {
            let archetype = archetypes[archetypeIndex]
            if entityIndex < archetype.entities.count {
                let entity = Entity(id: archetype.entities[entityIndex], world: world)
                entityIndex += 1
                if let filter, !world.queries.matches(filter, entityID: entity.id, in: world) {
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
        queries.register(query)
    }

    /// Unregister a previously registered query.
    public func unregister(_ query: Query) {
        queries.unregister(query)
    }

    /// Check if a query is registered.
    public func isRegistered(_ query: Query) -> Bool {
        queries.isRegistered(query)
    }

    /// Returns a lazy sequence of entities matching the query.
    /// If the query is registered, uses cached archetype matching for better performance.
    public func entities(matching query: Query) -> QuerySequence {
        trackStorageAccess()
        let selection = queries.prepare(query, requiring: [], in: self)
        return QuerySequence(world: self, archetypes: selection.archetypes, filter: selection.filter)
    }
}

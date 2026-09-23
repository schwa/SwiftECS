/// A predicate for matching entities based on their components.
public indirect enum QueryPredicate: Hashable, Sendable {
    /// Match entities that contain a specific component type.
    case contains(ComponentType)

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
        switch self {
        case .all:
            return true
        case .none:
            return false
        case let .contains(componentType):
            return signature.contains(componentType)
        case let .not(inner):
            return !inner.matches(signature)
        case let .and(predicates):
            return predicates.allSatisfy { $0.matches(signature) }
        case let .or(predicates):
            return predicates.contains { $0.matches(signature) }
        }
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
    public func query(_ query: Query) -> [Entity] {
        trackStorageAccess()
        var result: [Entity] = []
        for archetype in archetypes.values where query.matches(archetype.signature) {
            for entityID in archetype.entities {
                result.append(Entity(id: entityID, world: self))
            }
        }
        return result
    }

    /// Execute a query with component type requirements.
    public func query<each T: Component>(with types: repeat (each T).Type) -> [Entity] {
        query(Query(with: repeat each types))
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

    public func makeIterator() -> QueryIterator {
        world.trackStorageAccess()
        return QueryIterator(world: world, archetypes: archetypes)
    }
}

/// Iterator for QuerySequence.
public struct QueryIterator: IteratorProtocol {
    let world: World
    let archetypes: [Archetype]
    var archetypeIndex: Int = 0
    var entityIndex: Int = 0

    public mutating func next() -> Entity? {
        world.trackStorageAccess()
        while archetypeIndex < archetypes.count {
            let archetype = archetypes[archetypeIndex]
            if entityIndex < archetype.entities.count {
                let entity = Entity(id: archetype.entities[entityIndex], world: world)
                entityIndex += 1
                return entity
            }
            archetypeIndex += 1
            entityIndex = 0
        }
        return nil
    }
}

// MARK: - Fast Archetype-Based Iteration

/// A proxy for fast access to components directly from archetype storage.
public struct EntityRef {
    public let entityID: EntityID
    private let columns: [ComponentType: AnyColumn]
    private let index: Int
    private let world: World

    init(entityID: EntityID, columns: [ComponentType: AnyColumn], index: Int, world: World) {
        self.entityID = entityID
        self.columns = columns
        self.index = index
        self.world = world
    }

    /// Access a component by type.
    public subscript<C: Component>(type: C.Type) -> C {
        get {
            world.trackStorageAccess()
            guard let column = columns[ComponentType(type)] as? Column<C> else {
                preconditionFailure("Component \(type) was not requested by this fast query")
            }
            return column.data[index]
        }
        nonmutating set {
            defer { world.storageDidChange() }
            guard let column = columns[ComponentType(type)] as? Column<C> else {
                preconditionFailure("Component \(type) was not requested by this fast query")
            }
            column.data[index] = newValue
            // Notify observers
            world.notifyChanged(entityID: entityID, component: newValue)
        }
    }
}

/// Fast iterator for entities with specific components.
public struct FastQueryIterator: IteratorProtocol {
    let world: World
    let archetypes: [Archetype]
    let componentTypes: [ComponentType]
    var archetypeIndex: Int = 0
    var entityIndex: Int = 0
    var currentColumns: [ComponentType: AnyColumn]?

    init(world: World, archetypes: [Archetype], componentTypes: [ComponentType]) {
        self.world = world
        self.archetypes = archetypes
        self.componentTypes = componentTypes
        advanceToNextValidArchetype()
    }

    mutating func advanceToNextValidArchetype() {
        while archetypeIndex < archetypes.count {
            let archetype = archetypes[archetypeIndex]
            if let cols = getColumns(from: archetype) {
                currentColumns = cols
                return
            }
            archetypeIndex += 1
        }
        currentColumns = nil
    }

    func getColumns(from archetype: Archetype) -> [ComponentType: AnyColumn]? {
        var result: [ComponentType: AnyColumn] = [:]
        for type in componentTypes {
            guard let col = archetype.columns[type] else { return nil }
            result[type] = col
        }
        return result
    }

    public mutating func next() -> EntityRef? {
        world.trackStorageAccess()
        while archetypeIndex < archetypes.count {
            let archetype = archetypes[archetypeIndex]

            if entityIndex < archetype.entities.count, let cols = currentColumns {
                let ref = EntityRef(
                    entityID: archetype.entities[entityIndex],
                    columns: cols,
                    index: entityIndex,
                    world: world
                )
                entityIndex += 1
                return ref
            }

            archetypeIndex += 1
            entityIndex = 0
            advanceToNextValidArchetype()
        }
        return nil
    }
}

/// A fast sequence for iterating entities with specific components.
public struct FastQuerySequence: Sequence {
    let world: World
    let archetypes: [Archetype]
    let componentTypes: [ComponentType]

    public func makeIterator() -> FastQueryIterator {
        world.trackStorageAccess()
        return FastQueryIterator(world: world, archetypes: archetypes, componentTypes: componentTypes)
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
    public func entities(_ query: Query) -> QuerySequence {
        QuerySequence(world: self, archetypes: matchingArchetypes(for: query))
    }

    // Pack expansions use types; SwiftLint does not recognize the reference.
    // swiftlint:disable unused_parameter
    /// Returns a fast sequence for iterating entities with specific components.
    /// Uses direct archetype column access for maximum performance.
    public func entities<each T: Component>(
        _ query: Query,
        _ types: repeat (each T).Type
    ) -> FastQuerySequence {
        var componentTypes: [ComponentType] = []
        repeat componentTypes.append(ComponentType((each T).self))
        return FastQuerySequence(world: self, archetypes: matchingArchetypes(for: query), componentTypes: componentTypes)
    }

    // swiftlint:enable unused_parameter

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

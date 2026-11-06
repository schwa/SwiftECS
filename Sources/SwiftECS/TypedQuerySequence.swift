/// The entities that match a typed query. Created by ``World/query(_:matching:)``.
public struct TypedQuerySequence<each Value: Component>: Sequence {
    internal let world: World
    internal let storage: [TypedQueryStorage<repeat each Value>]
    internal let filter: QueryPredicate?

    public func makeIterator() -> TypedQueryIterator<repeat each Value> {
        world.trackStorageAccess()
        return TypedQueryIterator(world: world, storage: storage, filter: filter)
    }
}

@usableFromInline
internal final class TypedQueryStorage<each Value: Component> {
    @usableFromInline let archetype: Archetype
    @usableFromInline let columns: (repeat Column<each Value>)
    @usableFromInline let hasComponents: Bool

    init(archetype: Archetype) {
        self.archetype = archetype
        self.columns = (repeat Self.column((each Value).self, in: archetype))
        var hasComponents = false
        for _ in repeat (each Value).self {
            hasComponents = true
        }
        self.hasComponents = hasComponents
    }

    private static func column<T: Component>(_ type: T.Type, in archetype: Archetype) -> Column<T> {
        guard let column = archetype.columns[ComponentType(type)] as? Column<T> else {
            preconditionFailure("Typed query matched an archetype without component \(type)")
        }
        return column
    }
}

extension World {
    // Pack expansions use types; SwiftLint does not recognize the reference.
    // swiftlint:disable unused_parameter
    /// Returns the entities that have all the given component types and match the filter.
    ///
    /// Component types must be distinct.
    public func query<each Value: Component>(_ types: repeat (each Value).Type, matching query: Query = .all) -> TypedQuerySequence<repeat each Value> {
        trackStorageAccess()
        var requiredTypes = Set<ComponentType>()
        for type in repeat (each Value).self {
            precondition(requiredTypes.insert(ComponentType(type)).inserted, "Typed queries require distinct component types")
        }
        let selection = queries.prepare(query, requiring: requiredTypes, in: self)
        let storage = selection.archetypes.map { TypedQueryStorage<repeat each Value>(archetype: $0) }
        return TypedQuerySequence(world: self, storage: storage, filter: selection.filter)
    }
    // swiftlint:enable unused_parameter
}

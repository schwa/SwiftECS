/// One entity in a typed query, with direct access to the queried components.
public struct TypedEntityRef<each Value: Component> {
    /// The entity's ID.
    public let entityID: EntityID
    @usableFromInline internal let world: World
    @usableFromInline internal let index: Int
    @usableFromInline internal let storage: TypedQueryStorage<repeat each Value>

    @inlinable
    internal init(world: World, entityID: EntityID, index: Int, storage: TypedQueryStorage<repeat each Value>) {
        self.world = world
        self.entityID = entityID
        self.index = index
        self.storage = storage
    }

    /// References to the queried components, for repeated access.
    @inlinable
    public var components: (repeat ComponentRef<each Value>) {
        (repeat ComponentRef(world: world, entityID: entityID, column: each storage.columns, index: index))
    }

    /// The queried component values.
    @inlinable
    public var values: (repeat each Value) {
        world.trackStorageAccess()
        return (repeat read(each storage.columns))
    }

    /// Writes all queried components and notifies change observers after the writes finish.
    @inlinable
    public func set(_ values: repeat each Value) {
        guard storage.hasComponents else {
            return
        }
        // Read only when a change observer exists; which types it watches is checked per value below.
        var oldValues: (repeat each Value)?
        world.mutations.perform({
            if world.mutations.hasChangeObservers {
                oldValues = (repeat read(each storage.columns))
            }
            for (column, value) in repeat (each storage.columns, each values) {
                column.setValue(value, at: index)
            }
        }, events: {
            // Complete all writes before event handlers can change entity storage.
            if let oldValues {
                for (oldValue, value) in repeat (each oldValues, each values) {
                    world.notifyChanged(entityID: entityID, component: value, oldValue: oldValue)
                }
            } else if world.mutations.hasObservers {
                for value in repeat each values {
                    world.notifyChanged(entityID: entityID, component: value)
                }
            }
        })
    }

    // Direct array subscripting in a pack expansion fails as of Swift 6.4.
    @inlinable
    @inline(__always)
    internal func read<T: Component>(_ column: Column<T>) -> T {
        column.value(at: index)
    }
}

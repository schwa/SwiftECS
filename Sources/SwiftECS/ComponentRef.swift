/// A cached reference to one component of one entity, for fast repeated access.
///
/// A reference is valid until ``World/structuralRevision`` changes. Get one with ``World/componentRef(_:for:)``.
public struct ComponentRef<Value: Component> {
    /// The entity that owns the component.
    public let entityID: EntityID
    @usableFromInline internal let world: World
    @usableFromInline internal let column: Column<Value>
    @usableFromInline internal let index: Int

    @inlinable
    internal init(world: World, entityID: EntityID, column: Column<Value>, index: Int) {
        self.world = world
        self.entityID = entityID
        self.column = column
        self.index = index
    }

    /// The component value, read without registering Observation access on the world.
    @inlinable
    public var untrackedValue: Value {
        world.mutations.checkAccessible()
        return column.serialValue(at: index)
    }

    // Both accessors check that no parallel run is active first, so they skip the column lock (#49).
    /// The component value. Reads register Observation access, and writes notify change observers.
    @inlinable
    public var value: Value {
        get {
            world.trackStorageAccess()
            return column.serialValue(at: index)
        }
        nonmutating set {
            var oldValue: Value?
            world.mutations.perform({
                if world.mutations.hasChangeObservers(Value.self) {
                    oldValue = column.serialValue(at: index)
                }
                column.setSerialValue(newValue, at: index)
            }, events: {
                world.notifyChanged(entityID: entityID, component: newValue, oldValue: oldValue)
            })
        }
    }
}

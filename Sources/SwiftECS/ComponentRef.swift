public struct ComponentRef<Value: Component> {
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

    // Reads without registering Observation access on the World, for callers that do their own observation.
    @inlinable
    public var untrackedValue: Value {
        world.mutations.checkAccessible()
        return column.serialValue(at: index)
    }

    // Both accessors check that no parallel run is active first, so they skip the column lock (#49).
    @inlinable
    public var value: Value {
        get {
            world.trackStorageAccess()
            return column.serialValue(at: index)
        }
        nonmutating set {
            world.mutations.perform({
                column.setSerialValue(newValue, at: index)
            }, events: {
                world.notifyChanged(entityID: entityID, component: newValue)
            })
        }
    }
}

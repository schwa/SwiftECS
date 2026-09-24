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

    @inlinable
    public var value: Value {
        get {
            world.trackStorageAccess()
            return column.data[index]
        }
        nonmutating set {
            world.mutations.perform({
                column.setValue(newValue, at: index)
            }, events: {
                world.notifyChanged(entityID: entityID, component: newValue)
            })
        }
    }
}

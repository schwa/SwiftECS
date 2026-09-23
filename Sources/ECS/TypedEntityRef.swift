public struct TypedEntityRef<each Value: Component> {
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

    @inlinable
    public var components: (repeat ComponentRef<each Value>) {
        (repeat ComponentRef(world: world, entityID: entityID, column: each storage.columns, index: index))
    }

    @inlinable
    public var values: (repeat each Value) {
        world.trackStorageAccess()
        return (repeat read(each storage.columns))
    }

    @inlinable
    public func set(_ values: repeat each Value) {
        var changed = false
        defer {
            if changed {
                world.storageDidChange()
            }
        }
        for (column, value) in repeat (each storage.columns, each values) {
            column.setValue(value, at: index)
            changed = true
        }
        // Complete all writes before event handlers can change entity storage.
        for value in repeat each values {
            world.notifyChanged(entityID: entityID, component: value)
        }
    }

    // Direct array subscripting in a pack expansion fails on Swift 6.4.
    @inlinable
    internal func read<T: Component>(_ column: Column<T>) -> T {
        column.data[index]
    }
}

public struct TypedEntityRef<each Value: Component> {
    public let entityID: EntityID
    private let world: World
    private let index: Int
    private let storage: TypedQueryStorage<repeat each Value>

    internal init(world: World, entityID: EntityID, index: Int, storage: TypedQueryStorage<repeat each Value>) {
        self.world = world
        self.entityID = entityID
        self.index = index
        self.storage = storage
    }

    public var values: (repeat each Value) {
        world.trackStorageAccess()
        return (repeat read(each storage.columns))
    }

    public func set(_ values: repeat each Value) {
        var changed = false
        defer {
            if changed {
                world.storageDidChange()
            }
        }
        for (column, value) in repeat (each storage.columns, each values) {
            column.data[index] = value
            changed = true
        }
        // Complete all writes before event handlers can change entity storage.
        for value in repeat each values {
            world.notifyChanged(entityID: entityID, component: value)
        }
    }

    // Direct array subscripting in a pack expansion fails on Swift 6.4.
    private func read<T: Component>(_ column: Column<T>) -> T {
        column.data[index]
    }
}

@usableFromInline
internal final class SystemFieldAccess<Value: Component> {
    @usableFromInline let scope: SystemScope
    @usableFromInline let column: Column<Value>
    @usableFromInline let buffer: TaskColumn<Value>?
    @usableFromInline let revision: UInt64

    @usableFromInline
    init(scope: SystemScope, column: Column<Value>, buffer: TaskColumn<Value>?, revision: UInt64) {
        self.scope = scope
        self.column = column
        self.buffer = buffer
        self.revision = revision
    }

    @inlinable
    func read(entityID: EntityID, index: Int) -> Value {
        scope.checkActive()
        if let buffer {
            return buffer.values[index]
        }
        let world = scope.world
        if world.structuralRevision == revision {
            world.trackStorageAccess()
            return column.value(at: index)
        }
        guard let value = world.component(Value.self, for: entityID) else {
            preconditionFailure("System component \(Value.self) no longer exists on \(entityID)")
        }
        return value
    }

    @inlinable
    func write(_ value: Value, entityID: EntityID, index: Int) {
        scope.checkActive()
        if let buffer {
            buffer.set(value, at: index)
            return
        }
        let world = scope.world
        if world.structuralRevision == revision {
            var oldValue: Value?
            world.mutations.perform({
                if world.mutations.hasChangeObservers(Value.self) {
                    oldValue = column.value(at: index)
                }
                column.setValue(value, at: index)
            }, events: {
                world.notifyChanged(entityID: entityID, component: value, oldValue: oldValue)
            })
        } else {
            precondition(world.hasComponent(Value.self, for: entityID), "System writes cannot add missing components")
            world.addComponent(value, to: entityID)
        }
    }
}

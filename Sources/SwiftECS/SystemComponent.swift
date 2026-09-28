public struct SystemComponent<Value: Component> {
    public let entityID: EntityID
    internal let scope: SystemScope
    internal let reference: ComponentRef<Value>
    internal let revision: UInt64

    public var value: Value {
        get {
            scope.checkActive()
            if scope.world.structuralRevision == revision {
                return reference.value
            }
            guard let value = scope.world.component(Value.self, for: entityID) else {
                preconditionFailure("System component \(Value.self) no longer exists on \(entityID)")
            }
            return value
        }
        nonmutating set {
            scope.checkActive()
            if scope.world.structuralRevision == revision {
                reference.value = newValue
            } else {
                precondition(scope.world.hasComponent(Value.self, for: entityID), "System writes cannot add missing components")
                scope.world.addComponent(newValue, to: entityID)
            }
        }
    }
}

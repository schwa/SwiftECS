@frozen
public struct SystemComponent<Value: Component> {
    public let entityID: EntityID
    @usableFromInline internal let index: Int
    @usableFromInline internal let access: SystemFieldAccess<Value>
    internal var scope: SystemScope { access.scope }

    @inlinable
    internal init(entityID: EntityID, index: Int, access: SystemFieldAccess<Value>) {
        self.entityID = entityID
        self.index = index
        self.access = access
    }

    @inlinable
    public var value: Value {
        get { access.read(entityID: entityID, index: index) }
        nonmutating set { access.write(newValue, entityID: entityID, index: index) }
    }
}

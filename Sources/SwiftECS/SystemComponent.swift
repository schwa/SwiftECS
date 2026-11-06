/// A writable handle to a component in a system query row. Supplied by ``Write``.
///
/// The handle expires when the callback returns.
@frozen
public struct SystemComponent<Value: Component> {
    /// The entity that owns the component.
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

    /// The component value. Writes apply immediately.
    @inlinable
    public var value: Value {
        get { access.read(entityID: entityID, index: index) }
        nonmutating set { access.write(newValue, entityID: entityID, index: index) }
    }
}

/// A query term that supplies a writable ``SystemComponent`` handle.
public struct Write<Value: Component>: SystemTerm, Sendable {
    /// Creates the term.
    public init() {}

    @inlinable
    public var definition: SystemTermDefinition<Value, SystemComponent<Value>> {
        SystemTermDefinition(writes: true) { scope, column, buffer, revision in
            let access = SystemFieldAccess(scope: scope, column: column, buffer: buffer, revision: revision)
            return { id, index in SystemComponent(entityID: id, index: index, access: access) }
        }
    }
}

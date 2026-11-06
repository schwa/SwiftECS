/// A query term that supplies a component value.
public struct Read<Value: Component>: SystemTerm, Sendable {
    /// Creates the term.
    public init() {}

    @inlinable
    public var definition: SystemTermDefinition<Value, Value> {
        SystemTermDefinition(writes: false) { scope, column, buffer, revision in
            let access = SystemFieldAccess(scope: scope, column: column, buffer: buffer, revision: revision)
            return { id, index in access.read(entityID: id, index: index) }
        }
    }
}

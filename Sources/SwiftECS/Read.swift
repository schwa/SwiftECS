public struct Read<Value: Component>: SystemTerm, Sendable {
    public init() {}

    @inlinable
    public var definition: SystemTermDefinition<Value, Value> {
        SystemTermDefinition(writes: false) { scope, column, buffer, revision in
            let access = SystemFieldAccess(scope: scope, column: column, buffer: buffer, revision: revision)
            return { id, index in access.read(entityID: id, index: index) }
        }
    }
}

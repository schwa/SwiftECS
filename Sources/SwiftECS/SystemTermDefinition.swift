/// An opaque description of how a query term reads or writes a component column.
public struct SystemTermDefinition<Value: Component, Output> {
    @usableFromInline internal let writes: Bool
    @usableFromInline internal let bind: (SystemScope, Column<Value>, TaskColumn<Value>?, UInt64) -> (EntityID, Int) -> Output

    @inlinable
    internal init(writes: Bool, bind: @escaping (SystemScope, Column<Value>, TaskColumn<Value>?, UInt64) -> (EntityID, Int) -> Output) {
        self.writes = writes
        self.bind = bind
    }
}

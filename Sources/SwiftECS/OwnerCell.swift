// Non-Sendable, owner-isolated storage. Its address never reaches the public API.
@usableFromInline
internal final class OwnerCell<Value> {
    @usableFromInline let pointer: UnsafeMutablePointer<Value>

    init(_ value: Value) {
        pointer = .allocate(capacity: 1)
        pointer.initialize(to: value)
    }

    deinit {
        pointer.deinitialize(count: 1)
        pointer.deallocate()
    }

    @inlinable
    var value: Value {
        get { pointer.pointee }
        set { pointer.pointee = newValue }
        _modify { yield &pointer.pointee }
    }
}

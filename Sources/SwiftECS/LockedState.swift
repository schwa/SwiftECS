// The state never escapes the lock except as Sendable values.
internal final class LockedState<Value: Sendable>: @unchecked Sendable {
    private let lock = ScopedLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        try lock.withLock { try body(&value) }
    }
}

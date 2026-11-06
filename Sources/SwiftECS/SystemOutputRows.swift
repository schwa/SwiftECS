/// The rows a system query matches for one callback.
///
/// Membership is fixed for the callback. Iteration skips entities that lost a required component. The sequence
/// expires when the callback returns.
public struct SystemOutputRows<each Output>: Sequence {
    @usableFromInline internal let storage: [BoundSystemBatch<repeat each Output>]
    @usableFromInline internal let scope: SystemScope
    @usableFromInline internal let revision: UInt64
    @usableFromInline internal let required: Set<ComponentType>

    @usableFromInline
    internal init(storage: [BoundSystemBatch<repeat each Output>], scope: SystemScope, revision: UInt64, required: Set<ComponentType>) {
        self.storage = storage
        self.scope = scope
        self.revision = revision
        self.required = required
    }

    @inlinable
    public func makeIterator() -> SystemOutputIterator<repeat each Output> {
        scope.checkActive()
        return SystemOutputIterator(storage: storage, scope: scope, revision: revision, required: required)
    }
}

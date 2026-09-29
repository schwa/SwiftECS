extension World {
    /// Coalesce storage-observation notifications across `body`.
    ///
    /// Several sequential `update(deltaTime:)` calls normally publish one storage
    /// invalidation each. Wrapping them in this scope publishes a single storage
    /// invalidation when the outermost scope exits, so a per-frame simulation loop
    /// with multiple substeps notifies SwiftUI once instead of once per substep.
    ///
    /// Component-event observers are unaffected; they still fire synchronously.
    /// A thrown error still flushes the pending invalidation as the scope unwinds.
    /// This is a serial API: it cannot bracket the async parallel `update` overloads.
    public func batchingObservation<Result>(_ body: () throws -> Result) rethrows -> Result {
        try mutations.batch(body)
    }
}

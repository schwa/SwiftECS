/// A component that selects which registered systems a run executes.
///
/// Attach a pipeline to an entity and pass the entity to ``World/run(_:deltaTime:)-(Entity,_)``, or set ``World/defaultPipeline``
/// to change what ``World/update(deltaTime:)`` runs.
public struct Pipeline: Component, Hashable, Sendable {
    /// The query that system entities must match to be selected.
    public var query: Query
    /// When pending commands are merged between systems.
    public var synchronization: PipelineSynchronization

    /// Creates a pipeline.
    ///
    /// - Parameters:
    ///   - query: The query that selects system entities. The default selects every registered system.
    ///   - synchronization: When pending commands are merged between systems.
    public init(_ query: Query = .all, synchronization: PipelineSynchronization = .automatic) {
        self.query = query
        self.synchronization = synchronization
    }
}

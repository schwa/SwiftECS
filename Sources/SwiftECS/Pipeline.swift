public struct Pipeline: Component, Hashable, Sendable {
    public var query: Query
    public var synchronization: PipelineSynchronization

    public init(_ query: Query = .all, synchronization: PipelineSynchronization = .automatic) {
        self.query = query
        self.synchronization = synchronization
    }
}

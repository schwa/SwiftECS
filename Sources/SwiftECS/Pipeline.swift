public struct Pipeline: Component, Hashable, Sendable {
    public var query: Query

    public init(_ query: Query = .all) {
        self.query = query
    }
}

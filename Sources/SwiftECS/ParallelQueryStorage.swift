internal struct ParallelQueryStorage<each Value: ConcurrentComponent>: Sendable {
    let ids: [EntityID]
    let columns: (repeat ParallelColumnSnapshot<each Value>)
    let matchingIndices: [Int]?

    var count: Int { matchingIndices?.count ?? ids.count }

    init(storage: SystemQueryStorage<repeat each Value>) {
        ids = storage.ids
        columns = (repeat ParallelColumnSnapshot(column: each storage.columns))
        matchingIndices = storage.matchingIndices
    }

    func bind(in scope: SystemScope, slice: Range<Int>?) -> SystemQueryStorage<repeat each Value> {
        let indices = slice.map { range in range.map { matchingIndices?[$0] ?? $0 } }
        return SystemQueryStorage<repeat each Value>(ids: ids, columns: (repeat (each columns).column), matchingIndices: indices ?? matchingIndices, buffers: (repeat (each columns).bind(in: scope, indices: indices)), usesDenseIndices: slice != nil)
    }
}

internal struct PreparedParallelQuery<each Term: ParallelSystemTerm>: Sendable {
    let terms: (repeat each Term)
    let storage: [ParallelQueryStorage<repeat (each Term).ComponentValue>]

    var count: Int { storage.reduce(0) { $0 + $1.count } }

    func rows(scope: SystemScope, range: Range<Int>?) -> SystemRows<repeat each Term> {
        SystemQuery<repeat each Term>.bindRows(terms: (repeat each terms), storage: bindStorage(scope: scope, range: range), scope: scope, revision: 0)
    }

    func bindStorage(scope: SystemScope, range: Range<Int>?) -> [SystemQueryStorage<repeat (each Term).ComponentValue>] {
        var bound: [SystemQueryStorage<repeat (each Term).ComponentValue>] = []
        var offset = 0
        for batch in storage {
            if let range {
                let start = max(range.lowerBound, offset) - offset
                let end = min(range.upperBound, offset + batch.count) - offset
                if start < end {
                    bound.append(batch.bind(in: scope, slice: start..<end))
                }
            } else {
                bound.append(batch.bind(in: scope, slice: nil))
            }
            offset += batch.count
        }
        return bound
    }
}

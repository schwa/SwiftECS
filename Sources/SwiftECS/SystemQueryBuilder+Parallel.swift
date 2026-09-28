// Swift 6 capture checking is required, not a Swift 5 compatibility warning.
// swiftlint:disable incompatible_concurrency_annotation
extension SystemQueryBuilder where repeat each Term: ParallelSystemTerm {
    public func runParallel(_ body: @escaping @Sendable (SystemContext, SystemRows<repeat each Term>) throws -> Void) -> System {
        system.runParallel(query, body: body)
    }

    @inlinable
    public func eachParallel<each Input: ParallelCommandInput>(_ inputs: repeat each Input, minimumRowsPerTask: Int = 256, body: @escaping @Sendable (SystemContext, SystemRow<repeat each Term>, repeat (each Input).Value) throws -> Void) -> System {
        let terms = (repeat each query.terms)
        return makeEachParallel(repeat each inputs, minimumRowsPerTask: minimumRowsPerTask, queryBinding: query.binding, bindParallel: { scope, storage in
            SystemQuery<repeat each Term>.bindRows(terms: (repeat each terms), storage: storage, scope: scope, revision: 0)
        }, iterate: { (context: SystemContext, rows: SystemRows<repeat each Term>, commands: repeat (each Input).Value) in
            for row in rows {
                try Task.checkCancellation()
                try body(context, row, repeat each commands)
            }
        })
    }

    @usableFromInline
    internal func makeEachParallel<each Input: ParallelCommandInput>(_ inputs: repeat each Input, minimumRowsPerTask: Int, queryBinding: SystemBinding<SystemRows<repeat each Term>>, bindParallel: @escaping @Sendable (SystemScope, [SystemQueryStorage<repeat (each Term).ComponentValue>]) -> SystemRows<repeat each Term>, iterate: @escaping @Sendable (SystemContext, SystemRows<repeat each Term>, repeat (each Input).Value) throws -> Void) -> System {
        let bindings = (repeat (each inputs).parallelCommands.binding)
        var result = system.bind(queryBinding, repeat (each bindings).binding, body: iterate)
        let validate = result.validate
        result.validate = {
            try validate()
            guard minimumRowsPerTask > 0 else {
                throw SystemError.invalidPartitionSize
            }
        }
        result.prepareParallel = { world, deltaTime, identities, parallelism in
            let prepared = query.prepareParallel(in: world)
            let factories = (repeat (each bindings).prepare(world))
            let context = SystemContext(deltaTime: deltaTime, simulationTime: world.simulationTime)
            let count = prepared.count
            guard count > 0 else {
                return []
            }
            let partitions = min(parallelism, 1 + (count - 1) / minimumRowsPerTask)
            let size = 1 + (count - 1) / partitions
            return stride(from: 0, to: count, by: size).map { start in
                let range = start..<min(start + size, count)
                return ParallelJob(identities: identities) { scope in
                    let commands = (repeat (each factories)(scope))
                    try iterate(context, bindParallel(scope, prepared.bindStorage(scope: scope, range: range)), repeat each commands)
                }
            }
        }
        return result
    }
}
// swiftlint:enable incompatible_concurrency_annotation

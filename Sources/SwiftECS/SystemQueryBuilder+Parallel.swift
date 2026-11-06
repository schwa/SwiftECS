@usableFromInline
internal struct PartitionPlan {
    @usableFromInline let minimumRowsPerTask: Int
    @usableFromInline let tasksPerWorker: Int

    @inlinable
    init(minimumRowsPerTask: Int, tasksPerWorker: Int) {
        self.minimumRowsPerTask = minimumRowsPerTask
        self.tasksPerWorker = tasksPerWorker
    }
}

// Swift 6 capture checking is required, not a Swift 5 compatibility warning.
// swiftlint:disable incompatible_concurrency_annotation
extension SystemQueryBuilder where repeat each Term: ParallelSystemTerm {
    /// Returns a system whose callback receives all matching rows on one worker task.
    public func runParallel(_ body: @escaping @Sendable (SystemContext, SystemRows<repeat each Term>) throws -> Void) -> System {
        system.runParallel(query, body: body)
    }

    /// Runs `body` for each matching row across disjoint partitions.
    ///
    /// `minimumRowsPerTask` is the smallest partition size. `tasksPerWorker` splits the query into up to
    /// `parallelism * tasksPerWorker` partitions, but no partition is smaller than `minimumRowsPerTask`.
    /// Values above one let the worker pool balance uneven per-row work, but they add partitions.
    /// The default value of one gives one partition per worker.
    @inlinable
    public func eachParallel<each Input: ParallelCommandInput>(_ inputs: repeat each Input, minimumRowsPerTask: Int = 256, tasksPerWorker: Int = 1, body: @escaping @Sendable (SystemContext, SystemRow<repeat each Term>, repeat (each Input).Value) throws -> Void) -> System {
        let terms = (repeat each query.terms)
        let plan = PartitionPlan(minimumRowsPerTask: minimumRowsPerTask, tasksPerWorker: tasksPerWorker)
        return makeEachParallel(repeat each inputs, plan: plan, queryBinding: query.binding, bindParallel: { scope, storage in
            SystemQuery<repeat each Term>.bindRows(terms: (repeat each terms), storage: storage, scope: scope, revision: 0)
        }, iterate: { (context: SystemContext, rows: SystemRows<repeat each Term>, commands: repeat (each Input).Value) in
            for row in rows {
                try Task.checkCancellation()
                try body(context, row, repeat each commands)
            }
        })
    }

    @usableFromInline
    internal func makeEachParallel<each Input: ParallelCommandInput>(_ inputs: repeat each Input, plan: PartitionPlan, queryBinding: SystemBinding<SystemRows<repeat each Term>>, bindParallel: @escaping @Sendable (SystemScope, [SystemQueryStorage<repeat (each Term).ComponentValue>]) -> SystemRows<repeat each Term>, iterate: @escaping @Sendable (SystemContext, SystemRows<repeat each Term>, repeat (each Input).Value) throws -> Void) -> System {
        let bindings = (repeat (each inputs).parallelCommands.binding)
        var result = system.bind(queryBinding, repeat (each bindings).binding, body: iterate)
        let validate = result.validate
        result.validate = {
            try validate()
            guard plan.minimumRowsPerTask > 0, plan.tasksPerWorker > 0 else {
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
            let partitions = min(parallelism * plan.tasksPerWorker, 1 + (count - 1) / plan.minimumRowsPerTask)
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

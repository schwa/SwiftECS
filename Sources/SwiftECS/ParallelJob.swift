internal struct ParallelJob: Sendable {
    let execute: @Sendable () async -> ParallelJobResult

    init(execute: @escaping @Sendable () async -> ParallelJobResult) {
        self.execute = execute
    }

    init(identities: ParallelIDPool, body: @escaping @Sendable (SystemScope) throws -> Void) {
        self.init {
            let state = ParallelTaskState(identities: identities)
            let scope = SystemScope(parallel: state)
            var failure: (any Error)?
            do {
                try Task.checkCancellation()
                try body(scope)
                try Task.checkCancellation()
            } catch {
                failure = error
            }
            scope.isActive = false
            var result = state.finish(error: failure)
            result.valueUpdates = scope.finishColumns()
            result.didWrite = !result.valueUpdates.isEmpty
            return result
        }
    }
}

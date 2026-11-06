internal final class ParallelTaskState: Sendable {
    private struct State: Sendable {
        var active = true
        var commands: [@Sendable (World) throws -> Void] = []
        var reservedIDs: Set<EntityID> = []
    }

    private let state = LockedState(State())
    private let identities: ParallelIDPool

    init(identities: ParallelIDPool) {
        self.identities = identities
    }

    func reserve() -> EntityID {
        state.withLock {
            precondition($0.active, "Parallel inputs expired")
            let id = identities.reserve()
            $0.reservedIDs.insert(id)
            return id
        }
    }

    func enqueue(_ command: @escaping @Sendable (World) throws -> Void) {
        state.withLock {
            precondition($0.active, "Parallel inputs expired")
            $0.commands.append(command)
        }
    }

    func finish(error: (any Error)?) -> ParallelJobResult {
        state.withLock { state in
            state.active = false
            defer {
                state.commands.removeAll()
                state.reservedIDs.removeAll()
            }
            return ParallelJobResult(commands: error == nil ? state.commands : [], reservedIDs: error == nil ? state.reservedIDs : [], didWrite: false, error: error)
        }
    }
}

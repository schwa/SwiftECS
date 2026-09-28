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
        state.withLock {
            $0.active = false
            defer { $0.commands.removeAll(); $0.reservedIDs.removeAll() }
            return ParallelJobResult(commands: error == nil ? $0.commands : [], reservedIDs: error == nil ? $0.reservedIDs : [], didWrite: false, error: error)
        }
    }
}

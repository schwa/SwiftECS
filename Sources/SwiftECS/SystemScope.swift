@usableFromInline
internal final class SystemScope {
    @usableFromInline let owner: World?
    let parallel: ParallelTaskState?

    @inlinable
    var world: World {
        guard let owner else {
            preconditionFailure("Worker inputs cannot access World")
        }
        return owner
    }
    @usableFromInline var isParallel: Bool { parallel != nil }
    @usableFromInline let active = OwnerCell(true)
    @inlinable var isActive: Bool {
        get { active.value }
        set { active.value = newValue }
    }
    var commands: [(World) throws -> Void] = []
    var reservedIDs: Set<EntityID> = []
    var columns: [ObjectIdentifier: any AnyTaskColumn] = [:]

    func finishColumns() -> [ParallelValueUpdate] {
        defer { columns.removeAll() }
        return columns.values.compactMap { $0.finish() }
    }

    init(world: World) {
        owner = world
        parallel = nil
    }

    init(parallel: ParallelTaskState) {
        owner = nil
        self.parallel = parallel
    }

    @inlinable
    func checkActive() {
        precondition(isActive, "System inputs are only valid during their callback")
    }
}

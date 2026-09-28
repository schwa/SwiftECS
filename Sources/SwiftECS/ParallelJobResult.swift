internal struct ParallelJobResult: Sendable {
    let commands: [@Sendable (World) throws -> Void]
    let reservedIDs: Set<EntityID>
    var didWrite: Bool
    var valueUpdates: [ParallelValueUpdate] = []
    let error: (any Error)?
}

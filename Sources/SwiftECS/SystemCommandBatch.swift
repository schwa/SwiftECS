internal struct SystemCommandBatch {
    var commands: [(World) throws -> Void] = []
    var effects = CommandEffects()
    var reservedIDs: Set<EntityID> = []
}

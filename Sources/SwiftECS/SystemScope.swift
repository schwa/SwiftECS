internal final class SystemScope {
    let world: World
    var isActive = true
    var commands: [(World) throws -> Void] = []
    var reservedIDs: Set<EntityID> = []

    init(world: World) {
        self.world = world
    }

    func checkActive() {
        precondition(isActive, "System inputs are only valid during their callback")
    }
}

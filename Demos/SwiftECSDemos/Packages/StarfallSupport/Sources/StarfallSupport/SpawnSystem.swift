import ECS

final class SpawnSystem: System {
    private var remaining = 0.3
    private var count = 0

    func update(world: World, deltaTime: Double) {
        remaining -= deltaTime
        guard remaining <= 0 else {
            return
        }
        count += 1
        let difficulty = min(world.simulationTime / 60, 1)
        remaining += 0.8 - difficulty * 0.4
        world.createEntity(
            Position(x: Double.random(in: 0.08...0.92), y: -0.04),
            Velocity(y: 0.22 + difficulty * 0.22),
            FallingObject(kind: count.isMultiple(of: 4) ? .meteor : .star)
        )
    }
}

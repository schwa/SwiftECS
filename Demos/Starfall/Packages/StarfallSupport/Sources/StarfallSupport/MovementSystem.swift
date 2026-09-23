import ECS

struct MovementSystem: System {
    func update(world: World, deltaTime: Double) {
        for row in world.typedQuery(Position.self, Velocity.self) {
            var (position, velocity) = row.values
            position.y += velocity.y * deltaTime
            row.set(position, velocity)
        }
    }
}

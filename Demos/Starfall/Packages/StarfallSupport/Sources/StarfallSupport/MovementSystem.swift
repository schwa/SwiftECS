import ECS

struct MovementSystem: System {
    func update(world: World, deltaTime: Double) {
        for entity in world.query(with: Position.self, Velocity.self) {
            guard var position = entity[Position.self], let velocity = entity[Velocity.self] else {
                continue
            }
            position.y += velocity.y * deltaTime
            entity.set(position)
        }
    }
}

import SwiftECS

struct MovementSystem: System {
    func update(world: World, deltaTime: Double) {
        for row in world.query(Position.self, Velocity.self) {
            let (position, velocity) = row.components
            position.value.y += velocity.value.y * deltaTime
        }
    }
}

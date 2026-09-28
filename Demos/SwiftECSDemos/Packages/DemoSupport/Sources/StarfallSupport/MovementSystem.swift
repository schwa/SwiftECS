import SwiftECS

func movementSystem() -> System {
    System("movement").query(Write<Position>(), Read<Velocity>()).each { context, position, velocity in
        position.value.y += velocity.y * context.deltaTime
    }
}

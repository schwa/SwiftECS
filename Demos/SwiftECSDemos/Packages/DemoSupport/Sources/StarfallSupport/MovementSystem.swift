import SwiftECS

func movementSystem() -> System {
    System("movement").query(Write<Position>(), Read<Velocity>()).eachParallel { context, row in
        let (position, velocity) = row.fields
        position.value.y += velocity.y * context.deltaTime
    }
}

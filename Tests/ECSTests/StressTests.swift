@testable import ECS
import Foundation
import Testing

// Helper function to measure execution time
func measureTime(_ block: () -> Void) -> Double {
    let start = CFAbsoluteTimeGetCurrent()
    block()
    return (CFAbsoluteTimeGetCurrent() - start) * 1_000  // Convert to milliseconds
}

// MARK: - Additional Test Components

struct Transform: Component {
    var x: Double
    var y: Double
    var z: Double
}

struct Physics: Component {
    var velocityX: Double
    var velocityY: Double
    var velocityZ: Double
}

// MARK: - Entity Creation Tests

@Test func stressTestEntityCreation_10K() {
    let world = World()

    let time = measureTime {
        for _ in 0..<10_000 {
            world.createEntity()
        }
    }

    #expect(world.entityCount == 10_000)
    print("⏱ Created 10000 entities in \(String(format: "%.2f", time))ms")
}

@Test func stressTestEntityCreation_100K() {
    let world = World()

    let time = measureTime {
        for _ in 0..<100_000 {
            world.createEntity()
        }
    }

    #expect(world.entityCount == 100_000)
    print("⏱ Created 100000 entities in \(String(format: "%.2f", time))ms")
}

@Test func stressTestEntityWithComponents_10K() {
    let world = World()

    let time = measureTime {
        for i in 0..<10_000 {
            world.createEntity(
                Transform(x: Double(i), y: 0, z: 0),
                Physics(velocityX: 1, velocityY: 0, velocityZ: 0),
                Health(current: 100)
            )
        }
    }

    #expect(world.entityCount == 10_000)
    print("⏱ Created 10000 entities with 3 components in \(String(format: "%.2f", time))ms")
}

@Test func stressTestEntityWithComponents_100K() {
    let world = World()

    let time = measureTime {
        for i in 0..<100_000 {
            world.createEntity(
                Transform(x: Double(i), y: 0, z: 0),
                Physics(velocityX: 1, velocityY: 0, velocityZ: 0),
                Health(current: 100)
            )
        }
    }

    #expect(world.entityCount == 100_000)
    print("⏱ Created 100000 entities with 3 components in \(String(format: "%.2f", time))ms")
}

@Test func stressTestEntityRemoval_10K() {
    let world = World()
    var entities: [Entity] = []

    for i in 0..<10_000 {
        entities.append(world.createEntity( Position(x: Double(i), y: 0)))
    }

    let time = measureTime {
        for entity in entities {
            entity.destroy()
        }
    }

    #expect(world.entityCount == 0)
    print("⏱ Removed 10000 entities in \(String(format: "%.2f", time))ms")
}

// MARK: - Iteration Tests

@Test func stressTestForEach_100K() {
    let world = World()

    for i in 0..<100_000 {
        world.createEntity(
            Position(x: Double(i), y: 0),
            Velocity(dx: 1, dy: 1)
        )
    }

    var sum = 0.0
    let time = measureTime {
        world.forEach(Position.self, Velocity.self) { _, pos, vel in
            sum += pos.x + vel.dx
        }
    }

    #expect(sum > 0)
    print("⏱ forEach iteration (100K entities): \(String(format: "%.2f", time))ms")
}

@Test func stressTestPhysicsUpdate_100K() {
    let world = World()

    for i in 0..<100_000 {
        world.createEntity(
            Transform(x: Double(i), y: 0, z: 0),
            Physics(velocityX: 1, velocityY: 2, velocityZ: 0)
        )
    }

    let deltaTime = 1.0 / 60.0

    let time = measureTime {
        for _ in 0..<60 {
            world.forEachMutable(Transform.self, Physics.self) { _, transform, physics in
                transform.x += physics.velocityX * deltaTime
                transform.y += physics.velocityY * deltaTime
                transform.z += physics.velocityZ * deltaTime
            }
        }
    }

    print("⏱ 60 physics updates on 100000 entities in \(String(format: "%.2f", time))ms")
    print("   Average per frame: \(String(format: "%.2f", time / 60.0))ms")
}

@Test func stressTestSystemUpdate_100K() {
    let world = World()

    for i in 0..<100_000 {
        world.createEntity(
            Position(x: Double(i), y: 0),
            Velocity(dx: 1, dy: 2)
        )
    }

    world.addSystem(MovementSystem())

    let time = measureTime {
        for _ in 0..<60 {
            world.update(deltaTime: 1.0 / 60.0)
        }
    }

    print("⏱ 60 system updates on 100000 entities in \(String(format: "%.2f", time))ms")
    print("   Average per frame: \(String(format: "%.2f", time / 60.0))ms")
}

// MARK: - Query Tests

@Test func stressTestEntitiesQuery_100K() {
    let world = World()

    for i in 0..<100_000 {
        if i % 2 == 0 {
            world.createEntity( Position(x: Double(i), y: 0))
        } else {
            world.createEntity(
                Position(x: Double(i), y: 0),
                Velocity(dx: 1, dy: 1)
            )
        }
    }

    var total = 0
    let time = measureTime {
        for _ in 0..<100 {
            total += world.entities(with: Position.self).count
            total += world.entities(with: Velocity.self).count
            total += world.entities(with: Position.self, Velocity.self).count
        }
    }

    #expect(total > 0)
    print("⏱ 300 entities queries on 100000 entities in \(String(format: "%.2f", time))ms")
}

// MARK: - Mixed Operations Test

@Test func stressTestMixedOperations_50K() {
    let world = World()
    var entities: [Entity] = []

    // Create
    let createTime = measureTime {
        for i in 0..<50_000 {
            let entity = world.createEntity(
                Position(x: Double(i), y: 0),
                Velocity(dx: 1, dy: 1)
            )
            entities.append(entity)
        }
    }

    // Update (30 frames)
    let updateTime = measureTime {
        for _ in 0..<30 {
            world.forEachMutable(Position.self, Velocity.self) { _, pos, vel in
                pos.x += vel.dx
                pos.y += vel.dy
            }
        }
    }

    // Remove half
    let removeTime = measureTime {
        for i in stride(from: 0, to: entities.count, by: 2) {
            entities[i].destroy()
        }
    }

    // Add new entities
    let addTime = measureTime {
        for i in 0..<25_000 {
            world.createEntity(
                Position(x: Double(i), y: 0),
                Velocity(dx: -1, dy: -1)
            )
        }
    }

    let totalTime = createTime + updateTime + removeTime + addTime
    print("⏱ Mixed operations on 50000 entities:")
    print("   Create: \(String(format: "%.2f", createTime))ms")
    print("   Update (30 frames): \(String(format: "%.2f", updateTime))ms")
    print("   Remove half: \(String(format: "%.2f", removeTime))ms")
    print("   Add new: \(String(format: "%.2f", addTime))ms")
    print("   Total: \(String(format: "%.2f", totalTime))ms")
}

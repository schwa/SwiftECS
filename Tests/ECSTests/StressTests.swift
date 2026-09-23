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

@Suite(.enabled(if: ProcessInfo.processInfo.environment["ECS_RUN_STRESS_TESTS"] == "1"), .serialized)
struct StressTests {

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
            entities.append(world.createEntity(Position(x: Double(i), y: 0)))
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

    @Test func stressTestQueryIteration_100K() {
        let world = World()

        for i in 0..<100_000 {
            world.createEntity(
                Position(x: Double(i), y: 0),
                Velocity(dx: 1, dy: 1)
            )
        }

        var sum = 0.0
        let time = measureTime {
            for entity in world.query(with: Position.self, Velocity.self) {
                let (pos, vel) = entity.get(Position.self, Velocity.self)!.values
                sum += pos.x + vel.dx
            }
        }

        #expect(sum > 0)
        print("⏱ Query iteration (100K entities): \(String(format: "%.2f", time))ms")
    }

    @Test func stressTestRegisteredQueryIteration_100K() {
        let world = World()

        for i in 0..<100_000 {
            world.createEntity(
                Position(x: Double(i), y: 0),
                Velocity(dx: 1, dy: 1)
            )
        }

        let query = Query(with: Position.self, Velocity.self)
        world.register(query)
    
        var sum = 0.0
        let time = measureTime {
            for entity in world.entities(query) {
                let pos = entity[Position.self]!
                let vel = entity[Velocity.self]!
                sum += pos.x + vel.dx
            }
        }

        #expect(sum > 0)
        print("⏱ Registered query iteration (100K entities): \(String(format: "%.2f", time))ms")
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
                for entity in world.query(with: Transform.self, Physics.self) {
                    var (transform, physics) = entity.get(Transform.self, Physics.self)!.values
                    transform.x += physics.velocityX * deltaTime
                    transform.y += physics.velocityY * deltaTime
                    transform.z += physics.velocityZ * deltaTime
                    entity.set(transform, physics)
                }
            }
        }

        print("⏱ 60 physics updates on 100000 entities in \(String(format: "%.2f", time))ms")
        print("   Average per frame: \(String(format: "%.2f", time / 60.0))ms")
    }

    @Test func stressTestRegisteredPhysicsUpdate_100K() {
        let world = World()

        for i in 0..<100_000 {
            world.createEntity(
                Transform(x: Double(i), y: 0, z: 0),
                Physics(velocityX: 1, velocityY: 2, velocityZ: 0)
            )
        }

        let query = Query(with: Transform.self, Physics.self)
        world.register(query)
        let deltaTime = 1.0 / 60.0

        let time = measureTime {
            for _ in 0..<60 {
                for entity in world.entities(query) {
                    entity[Transform.self]!.x += entity[Physics.self]!.velocityX * deltaTime
                    entity[Transform.self]!.y += entity[Physics.self]!.velocityY * deltaTime
                    entity[Transform.self]!.z += entity[Physics.self]!.velocityZ * deltaTime
                }
            }
        }

        print("⏱ 60 registered physics updates on 100000 entities in \(String(format: "%.2f", time))ms")
        print("   Average per frame: \(String(format: "%.2f", time / 60.0))ms")
    }

    @Test func stressTestFastPhysicsUpdate_100K() {
        let world = World()

        for i in 0..<100_000 {
            world.createEntity(
                Transform(x: Double(i), y: 0, z: 0),
                Physics(velocityX: 1, velocityY: 2, velocityZ: 0)
            )
        }

        let query = Query(with: Transform.self, Physics.self)
        world.register(query)
        let deltaTime = 1.0 / 60.0

        let time = measureTime {
            for _ in 0..<60 {
                for ref in world.entities(query, Transform.self, Physics.self) {
                    ref[Transform.self].x += ref[Physics.self].velocityX * deltaTime
                    ref[Transform.self].y += ref[Physics.self].velocityY * deltaTime
                    ref[Transform.self].z += ref[Physics.self].velocityZ * deltaTime
                }
            }
        }

        print("⏱ 60 FAST physics updates on 100000 entities in \(String(format: "%.2f", time))ms")
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
                try! world.update(deltaTime: 1.0 / 60.0)
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
                world.createEntity(Position(x: Double(i), y: 0))
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
                total += world.query(with: Position.self).count
                total += world.query(with: Velocity.self).count
                total += world.query(with: Position.self, Velocity.self).count
            }
        }

        #expect(total > 0)
        print("⏱ 300 queries on 100000 entities in \(String(format: "%.2f", time))ms")
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
                for entity in world.query(with: Position.self, Velocity.self) {
                    var (pos, vel) = entity.get(Position.self, Velocity.self)!.values
                    pos.x += vel.dx
                    pos.y += vel.dy
                    entity.set(pos, vel)
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
}

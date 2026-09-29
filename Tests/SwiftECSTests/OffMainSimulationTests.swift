import SwiftECS
import Testing

// Proof of concept for issue #15: a simulation actor owns a World, applies
// Sendable input commands, ticks, and returns an immutable Sendable render
// snapshot. The main actor consumes the snapshot without ever touching the
// World, live entities, or query references. This compiles under strict Swift 6
// concurrency, which is the point: the boundary is enforced by the type system.

private struct RenderPoint: Sendable, Equatable {
    let id: EntityID
    let x: Double
    let y: Double
}

private struct RenderSnapshot: Sendable {
    let frame: Int
    let points: [RenderPoint]
}

private enum SimCommand: Sendable {
    case spawn(x: Double, y: Double, dx: Double)
    case advance(dt: Double)
}

// World is not Sendable, but it is confined to this actor's isolation and never
// escapes. Entities and query rows are also non-Sendable, so the compiler
// prevents them from leaving in the snapshot.
private actor SimulationActor {
    private let world = World()
    private var frame = 0
    private var configured = false

    private func configureIfNeeded() throws {
        guard !configured else {
            return
        }
        let movement = System("move").query(Write<Position>(), Read<Velocity>()).each { context, position, velocity in
            position.value.x += velocity.dx * context.deltaTime
            position.value.y += velocity.dy * context.deltaTime
        }
        try world.addSystem(movement)
        configured = true
    }

    func step(_ commands: [SimCommand]) throws -> RenderSnapshot {
        try configureIfNeeded()
        for command in commands {
            switch command {
            case let .spawn(x, y, dx):
                world.createEntity(Position(x: x, y: y), Velocity(dx: dx, dy: 0))
            case let .advance(dt):
                try world.update(deltaTime: dt)
            }
        }
        frame += 1
        var points: [RenderPoint] = []
        for row in world.query(Position.self) {
            let position: Position = row.values
            points.append(RenderPoint(id: row.entityID, x: position.x, y: position.y))
        }
        points.sort { $0.x < $1.x }
        return RenderSnapshot(frame: frame, points: points)
    }
}

@MainActor @Test func `an actor-owned world publishes a sendable snapshot to the main actor`() async throws {
    let simulation = SimulationActor()
    let spawn = try await simulation.step([.spawn(x: 0, y: 0, dx: 1), .spawn(x: 10, y: 0, dx: 2)])
    #expect(spawn.frame == 1)
    #expect(spawn.points.map(\.x) == [0, 10])

    let advanced = try await simulation.step([.advance(dt: 1)])
    #expect(advanced.frame == 2)
    // dx*dt advanced each entity: 0 -> 1 and 10 -> 12.
    #expect(advanced.points.map(\.x) == [1, 12])
    #expect(advanced.points.map(\.y) == [0, 0])

    // The snapshot is a plain value; the main actor holds no world reference.
    let published: RenderSnapshot = advanced
    #expect(published.points.count == 2)
}

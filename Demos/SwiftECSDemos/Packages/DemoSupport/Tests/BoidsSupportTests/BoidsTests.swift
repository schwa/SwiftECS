@testable import BoidsSupport
import SwiftECS
import Testing

@MainActor @Test func `the flock runs in parallel and stays in bounds`() async throws {
    let session = BoidsSession(count: 2_000)
    try await session.world.update(deltaTime: 1.0 / 60, parallelism: 4)
    #expect(session.failure == nil)
    #expect(session.world.lastRunStatistics.systemCount == 2)
    #expect(session.world.lastRunStatistics.parallelTaskCount > 0)
    for row in session.world.query(Boid.self) {
        let boid = row.values
        #expect(boid.position.x >= 0 && boid.position.x < BoidsSettings.bounds.x)
        #expect(boid.position.y >= 0 && boid.position.y < BoidsSettings.bounds.y)
    }
}

@MainActor @Test func `parallel and serial updates give the same flock`() async throws {
    let parallel = BoidsSession(count: 2_000)
    let serial = BoidsSession(count: 2_000)
    for _ in 0..<5 {
        try await parallel.world.update(deltaTime: 1.0 / 60, parallelism: 4)
        try serial.world.update(deltaTime: 1.0 / 60)
    }
    // A key path through the parameter-pack `values` crashes the compiler, so these use closures.
    // swiftlint:disable prefer_key_path
    let parallelPositions = parallel.world.query(Boid.self).map { $0.values.position }
    let serialPositions = serial.world.query(Boid.self).map { $0.values.position }
    // swiftlint:enable prefer_key_path
    #expect(parallelPositions == serialPositions)
}

@Test func `the grid finds neighbors across the wrapped edge`() {
    let near = Boid(position: [1, 500], velocity: [1, 0])
    let wrapped = Boid(position: [BoidsSettings.bounds.x - 1, 500], velocity: [1, 0])
    let grid = BoidGrid(boids: [near, wrapped])
    var offsets: [SIMD2<Double>] = []
    grid.forEachNeighbor(of: near.position) { offset, _ in offsets.append(offset) }
    #expect(offsets.contains([-2, 0]))
}

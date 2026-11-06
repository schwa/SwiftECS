import SwiftECS

// Hands the grid from the serial `index` system to the parallel `flock` system. `flock` depends on `index`, so
// the write always finishes before any worker starts, and workers only read.
final class BoidGridStore: @unchecked Sendable {
    var grid = BoidGrid.empty
}

enum BoidsSystems {
    static func install(in world: World) throws -> BoidGridStore {
        let store = BoidGridStore()
        let index = System("index")
            .query(Read<Boid>())
            .run { _, rows in
                store.grid = BoidGrid(boids: rows.map(\.fields))
            }
        let flock = System("flock")
            .query(Write<Boid>())
            .eachParallel(minimumRowsPerTask: 512) { (context: SystemContext, row: SystemRow<Write<Boid>>) in
                let boid: SystemComponent<Boid> = row.fields
                boid.value = steer(boid.value, in: store.grid, deltaTime: context.deltaTime)
            }
        try world.addSystem(index)
        try world.addSystem(flock, after: [index.id])
        return store
    }

    static func steer(_ boid: Boid, in grid: BoidGrid, deltaTime: Double) -> Boid {
        let neighborRadiusSquared = BoidsSettings.neighborRadius * BoidsSettings.neighborRadius
        let separationRadiusSquared = BoidsSettings.separationRadius * BoidsSettings.separationRadius
        var neighborCount = 0.0
        var offsetSum = SIMD2<Double>.zero
        var velocitySum = SIMD2<Double>.zero
        var separation = SIMD2<Double>.zero
        grid.forEachNeighbor(of: boid.position) { offset, velocity in
            let distanceSquared = (offset * offset).sum()
            guard distanceSquared > 1e-9, distanceSquared < neighborRadiusSquared else {
                return
            }
            neighborCount += 1
            offsetSum += offset
            velocitySum += velocity
            if distanceSquared < separationRadiusSquared {
                separation -= offset / distanceSquared
            }
        }

        var velocity = boid.velocity
        if neighborCount > 0 {
            let alignment = velocitySum / neighborCount - velocity
            let cohesion = offsetSum / neighborCount
            let acceleration = alignment * BoidsSettings.alignmentWeight
                + cohesion * BoidsSettings.cohesionWeight
                + separation * BoidsSettings.separationWeight
            velocity += acceleration * deltaTime
        }
        let speed = (velocity * velocity).sum().squareRoot()
        if speed > 0 {
            velocity *= min(max(speed, BoidsSettings.minimumSpeed), BoidsSettings.maximumSpeed) / speed
        }

        var position = boid.position + velocity * deltaTime
        let bounds = BoidsSettings.bounds
        position -= bounds * (position / bounds).rounded(.down)
        return Boid(position: position, velocity: velocity)
    }
}

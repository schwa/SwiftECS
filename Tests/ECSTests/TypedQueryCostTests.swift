import ECS
import Foundation
import Testing

private enum TypedQueryPhase: CaseIterable {
    case setup, iterate, read, write, retainedRead, retainedWrite
}

private final class TypedQueryCostSystem: System {
    let phase: TypedQueryPhase
    let query = Query(with: Transform.self, Physics.self)
    var retained: [TypedEntityRef<Transform, Physics>] = []
    var checksum: Double = 0
    var identityChecksum: UInt64 = 0
    var setups = 0

    init(phase: TypedQueryPhase) {
        self.phase = phase
    }

    func initialize(world: World) {
        world.register(query)
        if phase == .retainedRead || phase == .retainedWrite {
            retained = Array(world.query(Transform.self, Physics.self, matching: query))
        }
    }

    @inline(never)
    func update(world: World, deltaTime: Double) {
        switch phase {
        case .setup:
            for _ in 0..<1_000 {
                consume(world.query(Transform.self, Physics.self, matching: query))
            }
        case .iterate:
            var total: UInt64 = 0
            for row in world.query(Transform.self, Physics.self, matching: query) {
                total &+= row.entityID.value
            }
            identityChecksum = total
        case .read:
            checksum = read(world.query(Transform.self, Physics.self, matching: query))
        case .write:
            write(world.query(Transform.self, Physics.self, matching: query), deltaTime: deltaTime)
        case .retainedRead:
            checksum = read(retained)
        case .retainedWrite:
            write(retained, deltaTime: deltaTime)
        }
    }

    @inline(never)
    private func consume(_ sequence: TypedQuerySequence<Transform, Physics>) {
        withExtendedLifetime(sequence) { setups += 1 }
    }

    private func read<S: Sequence>(_ rows: S) -> Double where S.Element == TypedEntityRef<Transform, Physics> {
        var total = 0.0
        for row in rows {
            let (transform, physics) = row.values
            total += transform.x + physics.velocityX
        }
        return total
    }

    private func write<S: Sequence>(_ rows: S, deltaTime: Double) where S.Element == TypedEntityRef<Transform, Physics> {
        for row in rows {
            var (transform, physics) = row.values
            transform.x += physics.velocityX * deltaTime
            transform.y += physics.velocityY * deltaTime
            transform.z += physics.velocityZ * deltaTime
            row.set(transform, physics)
        }
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["ECS_RUN_BENCHMARKS"] == "1"), .serialized)
struct TypedQueryCostTests {
    @Test func isolateTypedQueryCosts() throws {
        var samples: [String: [Double]] = [:]
        let phases = TypedQueryPhase.allCases
        for round in 0..<3 {
            for offset in phases.indices {
                let phase = phases[(round + offset) % phases.count]
                let elapsed = try measure(phase: phase)
                samples["\(phase)", default: []].append(elapsed)
            }
        }
        for name in samples.keys.sorted() {
            guard let values = samples[name]?.sorted() else {
                continue
            }
            let text = "\(name): ms/update samples=\(values), median=\(values[1])\n"
            FileHandle.standardOutput.write(Data(text.utf8))
        }
    }

    private func measure(phase: TypedQueryPhase) throws -> Double {
        let world = World()
        var expectedIdentity: UInt64 = 0
        for index in 0..<100_000 {
            let entity = world.createEntity(Transform(x: Double(index), y: 0, z: 0), Physics(velocityX: 1, velocityY: 2, velocityZ: 3))
            expectedIdentity &+= entity.id.value
        }
        let system = TypedQueryCostSystem(phase: phase)
        try world.addSystem(system)
        for _ in 0..<2 {
            try world.update(deltaTime: 1.0 / 60)
        }
        let duration = try ContinuousClock().measure {
            for _ in 0..<10 {
                try world.update(deltaTime: 1.0 / 60)
            }
        }
        switch phase {
        case .setup:
            #expect(system.setups == 12_000)
        case .iterate:
            #expect(system.identityChecksum == expectedIdentity)
        case .read, .retainedRead:
            #expect(system.checksum == 5_000_050_000)
        case .write, .retainedWrite:
            #expect(world.query(Transform.self).allSatisfy { abs($0.values.y - 0.4) < 0.000001 })
        }
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return seconds * 100
    }
}

@testable import SwiftECS
import Testing

@MainActor @Test func `overlapping queries in a worker share writes before completion`() async throws {
    let world = World()
    let entity = world.createEntity(ConcurrentPosition(value: 1), ConcurrentHealth(value: 2))
    let system = System("aliases").runParallel(SystemQuery(Read<ConcurrentPosition>()), SystemQuery(Write<ConcurrentPosition>())) { _, read, write in
        let original = try #require(read.first { _ in true }).fields
        let reference = try #require(write.first { _ in true }).fields
        reference.value.value = 9
        #expect(original.value == 1)
        #expect(read.first { _ in true }?.fields.value == 9)
        #expect(reference.value.value == 9)
    }
    try await world.run(system, deltaTime: 0, parallelism: 2)
    #expect(entity[ConcurrentPosition.self]?.value == 9)
}

@MainActor @Test func `filtered worker writeback changes only visited components`() async throws {
    let world = World()
    let parent = world.createEntity()
    var expected: [EntityID] = []
    var unchanged: [EntityID] = []
    for index in 0..<73 {
        let entity = world.createEntity(ConcurrentPosition(value: index))
        if index.isMultiple(of: 3) {
            try entity.setParent(parent)
            expected.append(entity.id)
        } else {
            unchanged.append(entity.id)
        }
    }
    let system = System("filtered").query(Write<ConcurrentPosition>(), matching: Query(.related(ChildOf.self, to: parent.id))).eachParallel(minimumRowsPerTask: 1) { _, row in
        row.fields.value.value += 100
    }
    try await world.run(system, deltaTime: 0, parallelism: 4)
    #expect(expected.allSatisfy { world[$0]![ConcurrentPosition.self]!.value >= 100 })
    #expect(unchanged.allSatisfy { world[$0]![ConcurrentPosition.self]!.value < 100 })
}

@MainActor @Test func `worker updates are applied before dependent queries and structural commands`() async throws {
    let world = World()
    let entity = world.createEntity(ConcurrentPosition(value: 1))
    let id = entity.id
    try world.addSystem(System("write").runParallel(SystemQuery(Write<ConcurrentPosition>()), EditComponent<ConcurrentHealth>()) { _, rows, health in
        for row in rows { row.fields.value.value = 8 }
        try health.set(ConcurrentHealth(value: 3), on: id)
    })
    try world.addSystem(System("read").query(Read<ConcurrentPosition>(), Read<ConcurrentHealth>()).runParallel { _, rows in
        #expect(rows.count { $0.fields.0.value == 8 && $0.fields.1.value == 3 } == 1)
    })
    try await world.update(deltaTime: 0, parallelism: 4)
    #expect(entity[ConcurrentPosition.self]?.value == 8)
    #expect(entity[ConcurrentHealth.self]?.value == 3)
}

@MainActor @Test func `unchanged worker buffers do not overwrite another querys edits`() async throws {
    let world = World()
    let entity = world.createEntity(ConcurrentHealth(value: 1), ConcurrentPosition(value: 2))
    let system = System("multiple").runParallel(SystemQuery(Read<ConcurrentHealth>(), Write<ConcurrentPosition>()), SystemQuery(Write<ConcurrentHealth>())) { _, first, second in
        for row in second { row.fields.value.value += 10 }
        for row in first { #expect(row.fields.0.value == 11) }
    }
    try await world.run(system, deltaTime: 0, parallelism: 2)
    #expect(entity[ConcurrentHealth.self]?.value == 11)
    #expect(entity[ConcurrentPosition.self]?.value == 2)
}

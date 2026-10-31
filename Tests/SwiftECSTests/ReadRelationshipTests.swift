@testable import SwiftECS
import Testing

@Test func `systems read relationship targets and sources per row`() throws {
    let world = World()
    let root = world.createEntity()
    let child = world.createEntity(Health(current: 1))
    try child.setParent(root)
    var parents: [EntityID: EntityID] = [:]
    var children: [EntityID] = []
    try world.run(System("read").run(SystemQuery(Read<Health>()), ReadRelationship<ChildOf>()) { _, rows, links in
        for row in rows {
            parents[row.entityID] = links.target(of: row.entityID)
        }
        children = links.sources(of: root.id)
    }, deltaTime: 0)
    #expect(parents == [child.id: root.id])
    #expect(children == [child.id])
}

@Test func `relationship reads synchronize after relationship edits`() throws {
    let world = World()
    let root = world.createEntity()
    let child = world.createEntity()
    try world.addSystem(System("link").run(EditRelationship<ChildOf>()) { _, links in links.add(from: child.id, to: root.id) })
    var observed: EntityID?
    try world.addSystem(System("read").run(ReadRelationship<ChildOf>()) { _, links in observed = links.target(of: child.id) })
    try world.update(deltaTime: 0)
    #expect(observed == root.id)
    #expect(world.lastRunStatistics.mergeCount == 1)
}

@MainActor @Test func `parallel systems read relationship endpoints`() async throws {
    let world = World()
    let root = world.createEntity()
    var expected: Set<EntityID> = []
    for index in 0..<40 {
        let child = world.createEntity(ConcurrentHealth(value: index))
        try child.setParent(root)
        expected.insert(child.id)
    }
    let rootID = root.id
    let system = System("read").runParallel(SystemQuery(Write<ConcurrentHealth>()), ReadRelationship<ChildOf>()) { _, rows, links in
        for row in rows {
            row.fields.value.value = links.target(of: row.entityID) == rootID ? 1 : 0
        }
    }
    try await world.run(system, deltaTime: 0, parallelism: 3)
    #expect(world.snapshot(with: ConcurrentHealth.self).allSatisfy { $0[ConcurrentHealth.self]?.value == 1 })
    #expect(Set(root.children.map(\.id)) == expected)
}

import Observation
import SwiftECS
import Testing

private struct Gameplay: Component {}
private struct Service: Component {}

private final class PipelineLog {
    var entries: [String] = []
}

private func pipelineTestSystem(name: String, log: PipelineLog, action: @escaping () -> Void = {}) -> System {
    System(SystemID(name))
        .run { _ in
            log.entries.append(name)
            action()
        }
        .onCleanup {
            log.entries.append("cleanup-\(name)")
        }
}

@Test func `phase DAG orders all selected systems across unequal paths`() throws {
    let world = World()
    let log = PipelineLog()
    let root = try world.createPhase("root")
    let left = try world.createPhase("left", after: [root])
    let middle = try world.createPhase("middle", after: [root])
    let right = try world.createPhase("right", after: [middle])
    let end = try world.createPhase("end", after: [left, right])
    try world.addSystem(pipelineTestSystem(name: "end", log: log), id: "end", phase: end)
    try world.addSystem(pipelineTestSystem(name: "right", log: log), id: "right", phase: right)
    try world.addSystem(pipelineTestSystem(name: "left", log: log), id: "left", phase: left)
    try world.addSystem(pipelineTestSystem(name: "root", log: log), id: "root", phase: root)
    try world.addSystem(pipelineTestSystem(name: "root2", log: log), id: "root2", phase: root)
    try world.update(deltaTime: 1)
    #expect(log.entries == ["root", "root2", "right", "left", "end"])
}

@Test func `ready systems use registration order rather than query storage order`() throws {
    let world = World()
    let log = PipelineLog()
    let first = try world.addSystem(pipelineTestSystem(name: "first", log: log), id: "first", after: ["second"])
    try world.addSystem(pipelineTestSystem(name: "second", log: log), id: "second")
    try world.addSystem(pipelineTestSystem(name: "third", log: log), id: "third")
    first.set(Gameplay())
    #expect(try world.systemExecutionOrder == ["second", "first", "third"])
    #expect(first.targets(of: DependsOn.self).first?[SystemDescriptor.self]?.id == "second")
}

@Test func `pipelines select systems without implicitly executing phase predecessors`() throws {
    let world = World()
    let log = PipelineLog()
    let early = try world.createPhase("early")
    let late = try world.createPhase("late", after: [early])
    try world.addSystem(pipelineTestSystem(name: "game", log: log), id: "game", phase: early).set(Gameplay())
    try world.addSystem(pipelineTestSystem(name: "service", log: log), id: "service", phase: late).set(Service())
    world.createEntity(Service())
    let pipeline = world.createEntity(Pipeline(Query(with: Service.self)))
    try world.run(pipeline, deltaTime: 1)
    #expect(log.entries == ["service"])
    #expect(world.simulationTime == 0)
    pipeline.set(Pipeline(Query(with: Gameplay.self)))
    try world.run(pipeline, deltaTime: 1)
    #expect(log.entries == ["service", "game"])
    world.defaultPipeline = Pipeline(Query(with: Service.self))
    try world.update(deltaTime: 2)
    #expect(log.entries == ["service", "game", "service"])
    #expect(world.simulationTime == 2)
}

@Test func `excluded explicit dependencies fail before execution or time advances`() throws {
    let world = World()
    let log = PipelineLog()
    try world.addSystem(pipelineTestSystem(name: "first", log: log), id: "first")
    try world.addSystem(pipelineTestSystem(name: "second", log: log), id: "second", dependencies: ["first"]).set(Gameplay())
    world.defaultPipeline = Pipeline(Query(with: Gameplay.self))
    #expect(throws: SystemError.excludedDependency(system: "second", dependency: "first")) {
        try world.update(deltaTime: 1)
    }
    #expect(log.entries.isEmpty)
    #expect(world.simulationTime == 0)
}

@Test func `phase and system constraints are validated together`() throws {
    let world = World()
    let log = PipelineLog()
    let early = try world.createPhase("early")
    let late = try world.createPhase("late", after: [early])
    try world.addSystem(pipelineTestSystem(name: "first", log: log), id: "first", phase: early, after: ["second"])
    try world.addSystem(pipelineTestSystem(name: "second", log: log), id: "second", phase: late)
    #expect(throws: SystemError.cyclicDependency(["first", "second"])) {
        try world.update(deltaTime: 1)
    }
    #expect(log.entries.isEmpty)
}

@Test func `reachable phase cycles fail including empty phases`() throws {
    let world = World()
    let log = PipelineLog()
    let first = try world.createPhase("first")
    let second = try world.createPhase("second", after: [first])
    try first.addRelationship(DependsOn.self, to: second)
    try world.addSystem(pipelineTestSystem(name: "system", log: log), phase: second)
    #expect(throws: SystemError.phaseCycle(second.id)) { try world.update(deltaTime: 1) }
    #expect(log.entries.isEmpty)
    try first.removeRelationship(DependsOn.self, to: second)
    try world.update(deltaTime: 1)
    #expect(log.entries == ["system"])
}

@Test func `runtime relationship edits rebuild the next schedule`() throws {
    let world = World()
    let log = PipelineLog()
    let first = try world.createPhase("first")
    let second = try world.createPhase("second")
    try world.addSystem(pipelineTestSystem(name: "A", log: log), id: "A", phase: first)
    let system = try world.addSystem(pipelineTestSystem(name: "B", log: log), id: "B", phase: second)
    #expect(try world.systemExecutionOrder == ["A", "B"])
    try first.addRelationship(DependsOn.self, to: second)
    #expect(try world.systemExecutionOrder == ["B", "A"])
    try system.addRelationship(InPhase.self, to: first)
    #expect(try world.systemExecutionOrder == ["A", "B"])
}

@Test func `pipeline membership changes during a run affect the next snapshot`() throws {
    let world = World()
    let log = PipelineLog()
    var target: Entity?
    let first = pipelineTestSystem(name: "A", log: log) {
        target?.remove(Gameplay.self)
    }
    try world.addSystem(first, id: "A").set(Gameplay())
    target = try world.addSystem(pipelineTestSystem(name: "B", log: log), id: "B").set(Gameplay())
    let pipeline = Pipeline(Query(with: Gameplay.self))
    world.register(pipeline.query.with(SystemDescriptor.self))
    try world.run(pipeline, deltaTime: 1)
    try world.run(pipeline, deltaTime: 1)
    #expect(log.entries == ["A", "B", "A"])
}

@Test func `removal during execution retains the snapshot and defers cleanup`() throws {
    let world = World()
    let log = PipelineLog()
    let first = pipelineTestSystem(name: "A", log: log) {
        world.removeAllSystems()
        #expect(world.systemCount == 0)
        #expect(log.entries == ["A"])
    }
    try world.addSystem(first, id: "A")
    try world.addSystem(pipelineTestSystem(name: "B", log: log), id: "B")
    try world.update(deltaTime: 1)
    #expect(Array(log.entries.prefix(2)) == ["A", "B"])
    #expect(Set(log.entries.suffix(2)) == ["cleanup-A", "cleanup-B"])
    try world.update(deltaTime: 1)
    #expect(log.entries.count == 4)
}

@Test func `new registrations start on the next run`() throws {
    let world = World()
    let log = PipelineLog()
    var registered = false
    let first = pipelineTestSystem(name: "A", log: log) {
        if !registered {
            registered = true
            do {
                try world.addSystem(pipelineTestSystem(name: "B", log: log), id: "B")
            } catch {
                Issue.record(error)
            }
        }
    }
    try world.addSystem(first, id: "A")
    try world.update(deltaTime: 1)
    #expect(log.entries == ["A"])
    try world.update(deltaTime: 1)
    #expect(log.entries == ["A", "A", "B"])
}

@Test func `missing and invalid phase metadata fails before execution`() throws {
    let world = World()
    let log = PipelineLog()
    let phase = try world.createPhase("phase")
    let system = try world.addSystem(pipelineTestSystem(name: "A", log: log), id: "A", phase: phase)
    phase.remove(Phase.self)
    #expect(throws: SystemError.invalidPhase(phase.id)) { try world.update(deltaTime: 1) }
    try world.destroy(phase)
    #expect(throws: SystemError.missingPhase("A")) { try world.update(deltaTime: 1) }
    #expect(try world.clone(system) == nil)
    #expect(log.entries.isEmpty)
}

@Test func `foreign scheduling handles fail without registration side effects`() throws {
    let world = World()
    let other = World()
    let log = PipelineLog()
    let phase = try other.createPhase("foreign")
    #expect(throws: RelationshipError.differentWorlds) {
        try world.addSystem(pipelineTestSystem(name: "A", log: log), phase: phase)
    }
    #expect(world.entityCount == 0)
    #expect(throws: RelationshipError.differentWorlds) {
        try world.run(other.createEntity(Pipeline()), deltaTime: 1)
    }
    let invalid = world.createEntity()
    #expect(throws: SystemError.invalidPipeline(invalid.id)) { try world.run(invalid, deltaTime: 1) }
}

@Test func `before sugar and unresolved references use ECS relationships`() throws {
    let world = World()
    let log = PipelineLog()
    let first = try world.addSystem(pipelineTestSystem(name: "A", log: log), id: "A", before: ["B"])
    let reference = try #require(world.systemEntity(for: "B"))
    #expect(reference[SystemDescriptor.self]?.isRegistered == false)
    #expect(reference.hasRelationship(DependsOn.self, to: first))
    #expect(world.systemCount == 1)
    let second = try world.addSystem(pipelineTestSystem(name: "B", log: log), id: "B")
    #expect(reference.id == second.id)
    #expect(try world.systemExecutionOrder == ["A", "B"])
}

// Observation callbacks run synchronously in these tests.
private final class ScheduleChanges: @unchecked Sendable {
    var count = 0
    let read: () -> Void

    init(_ read: @escaping () -> Void) {
        self.read = read
        arm()
    }

    func arm() {
        withObservationTracking(read) { [weak self] in
            guard let self else {
                return
            }
            count += 1
            arm()
        }
    }
}

@Test func `scheduling changes notify storage and system counts`() throws {
    let world = World()
    let log = PipelineLog()
    let changes = ScheduleChanges { _ = world.systemCount }
    let system = try world.addSystem(pipelineTestSystem(name: "A", log: log), id: "A")
    #expect(changes.count == 1)
    let phase = try world.createPhase("new")
    #expect(changes.count == 2)
    try system.addRelationship(InPhase.self, to: phase)
    #expect(changes.count == 3)
    let pipeline = world.createEntity(Pipeline())
    #expect(changes.count == 4)
    pipeline.set(Pipeline(.none))
    #expect(changes.count == 5)
    try world.run(pipeline, deltaTime: 1)
    #expect(changes.count == 5)
    try world.destroy(system)
    #expect(changes.count == 6)
    #expect(world.systemCount == 0)
    #expect(log.entries == ["cleanup-A"])
}

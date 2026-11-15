import Observation
import SwiftECS
import Testing

private final class ChangeFlag: @unchecked Sendable {
    var changed = false
}

private func tracksChange(_ read: () -> Void, write: () throws -> Void) rethrows -> Bool {
    let flag = ChangeFlag()
    withObservationTracking(read) { flag.changed = true }
    try write()
    return flag.changed
}

@Test func `a plain world does not take part in observation`() throws {
    let world = World()
    let entity = world.createEntity(Health(current: 1))
    #expect(!tracksChange({ _ = world.entityCount }, write: { world.createEntity() }))
    #expect(!tracksChange({ _ = entity[Health.self] }, write: { entity.set(Health(current: 2)) }))
    #expect(try !tracksChange({ _ = world.simulationTime }, write: { try world.update(deltaTime: 1) }))
    #expect(!tracksChange({ _ = world.defaultPipeline }, write: { world.defaultPipeline = Pipeline() }))
    #expect(entity[Health.self]?.current == 2)
    #expect(world.simulationTime == 1)
}

@Test func `an observable world tracks storage time and pipeline reads`() throws {
    let observable = ObservableWorld()
    let world = observable.world
    let entity = world.createEntity(Health(current: 1))
    #expect(tracksChange({ _ = world.entityCount }, write: { world.createEntity() }))
    #expect(tracksChange({ _ = entity[Health.self] }, write: { entity.set(Health(current: 2)) }))
    #expect(try tracksChange({ _ = world.simulationTime }, write: { try world.update(deltaTime: 1) }))
    #expect(tracksChange({ _ = world.defaultPipeline }, write: { world.defaultPipeline = Pipeline() }))
    #expect(!tracksChange({ _ = world.simulationTime }, write: { world.createEntity() }))
}

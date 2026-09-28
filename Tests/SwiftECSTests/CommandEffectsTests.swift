@testable import SwiftECS
import Testing

@Test func `typed commands describe creation signatures component edits and relationships`() throws {
    let world = World()
    var created: EntityID?
    let parent = world.createEntity()
    let system = System("commands").run(CreateEntities(Position.self, Velocity.self), EditComponent<Health>(), EditRelationship<ChildOf>()) { _, creator, health, links in
        created = try creator.create(Position(x: 1, y: 2), Velocity(dx: 3, dy: 4))
        try health.set(Health(current: 10), on: created!)
        links.add(from: created!, to: parent.id)
    }
    let effects = system.access.commandEffects
    #expect(effects.creationSignatures == [[ComponentType(Position.self), ComponentType(Velocity.self)]])
    #expect(effects.components == [ComponentType(Health.self)])
    #expect(effects.relationships == [RelationshipType(ChildOf.self)])
    #expect(!effects.isUnrestricted)
    #expect(!effects.destroysEntities)
    try world.run(system, deltaTime: 0)
    #expect(world[created!]?[Health.self]?.current == 10)
    #expect(world[created!]?.parent?.id == parent.id)
    try world.run(System("remove").run(EditComponent<Health>(), EditRelationship<ChildOf>()) { _, health, links in
        health.remove(from: created!)
        links.remove(from: created!, to: parent.id)
    }, deltaTime: 0)
    #expect(world[created!]?[Health.self] == nil)
    #expect(world[created!]?.parent == nil)
}

@Test func `destruction includes arbitrary component and relationship cleanup`() throws {
    let world = World()
    let parent = world.createEntity(Health(current: 1))
    let child = world.createEntity()
    try child.setParent(parent)
    let destroy = System("destroy").run(DestroyEntities()) { _, commands in commands.destroy(parent.id) }
    #expect(destroy.access.commandEffects.destroysEntities)
    #expect(destroy.access.commandEffects.requiresBarrier)
    #expect(Commands().binding.access.commandEffects.isUnrestricted)
    try world.run(destroy, deltaTime: 0)
    #expect(child.parent == nil)
    #expect(!parent.exists)
}

private final class CommandReference: Component {}

@Test func `typed creation rejects classes and duplicate component types`() throws {
    let world = World()
    #expect(throws: SystemError.referenceComponent(ComponentType(CommandReference.self))) {
        try world.addSystem(System("class").run(CreateEntities(CommandReference.self)) { _, _ in })
    }
    #expect(throws: SystemError.referenceComponent(ComponentType(CommandReference.self))) {
        try world.addSystem(System("edit").run(EditComponent<CommandReference>()) { _, _ in })
    }
    #expect(throws: SystemError.duplicateTerm(ComponentType(Health.self))) {
        try world.addSystem(System("duplicate").run(CreateEntities(Health.self, Health.self)) { _, _ in })
    }
    #expect(world.entityCount == 0)
}

@Test func `deferred component set reports missing targets while removal is idempotent`() throws {
    let world = World()
    let missing = EntityID()
    #expect(throws: SystemError.missingCommandEntity(missing)) {
        try world.run(System("missing").run(EditComponent<Health>()) { _, health in
            try health.set(Health(current: 1), on: missing)
        }, deltaTime: 0)
    }
    try world.run(System("remove").run(EditComponent<Health>()) { _, health in health.remove(from: missing) }, deltaTime: 0)
}

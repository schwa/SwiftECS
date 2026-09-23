import ECS
import Testing

private final class RegistrationSystem: System {
    var initializations = 0

    func initialize(world _: World) {
        initializations += 1
    }

    func update(world _: World, deltaTime _: Double) {}
}

@Test func `default system registration throws on duplicates without initializing them`() throws {
    let world = World()
    let original = RegistrationSystem()
    let duplicate = RegistrationSystem()
    try world.addSystem(original)
    #expect(throws: SystemError.duplicateID(SystemID.of(RegistrationSystem.self))) {
        try world.addSystem(duplicate)
    }
    #expect(world.systemCount == 1)
    #expect(original.initializations == 1)
    #expect(duplicate.initializations == 0)
    try world.addSystem(duplicate, id: "second")
    #expect(world.systemCount == 2)
    #expect(duplicate.initializations == 1)
}

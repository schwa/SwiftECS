import SwiftECS
import Testing

private final class RegistrationSystem {
    var initializations = 0

    var system: System {
        System(.of(Self.self)).onInitialize { self.initializations += 1 }
    }
}

@Test func `default system registration throws on duplicates without initializing them`() throws {
    let world = World()
    let original = RegistrationSystem()
    let duplicate = RegistrationSystem()
    try world.addSystem(original.system)
    #expect(throws: SystemError.duplicateID(SystemID.of(RegistrationSystem.self))) {
        try world.addSystem(duplicate.system)
    }
    #expect(world.systemCount == 1)
    #expect(original.initializations == 1)
    #expect(duplicate.initializations == 0)
    try world.addSystem(duplicate.system, id: "second")
    #expect(world.systemCount == 2)
    #expect(duplicate.initializations == 1)
}

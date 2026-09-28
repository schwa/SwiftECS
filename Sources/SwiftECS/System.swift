public struct System {
    public let id: SystemID
    public private(set) var access = SystemAccess()
    internal var validate: () throws -> Void = {}
    internal var initialize: () -> Void = {}
    internal var cleanup: () -> Void = {}
    internal var execute: (World, Double) throws -> SystemCommandBatch = { _, _ in SystemCommandBatch() }

    public init(_ id: SystemID) {
        self.id = id
    }

    public func query<each Term: SystemTerm>(_ terms: repeat each Term, matching filter: Query = .all) -> SystemQueryBuilder<repeat each Term> {
        SystemQueryBuilder(system: self, query: SystemQuery(repeat each terms, matching: filter))
    }

    public func run<each Input: SystemInput>(_ inputs: repeat each Input, body: @escaping (SystemContext, repeat (each Input).Value) throws -> Void) -> System {
        var system = self
        let bindings = (repeat (each inputs).binding)
        var access = SystemAccess()
        repeat access.merge((each bindings).access)
        system.access = access
        system.validate = {
            repeat try (each bindings).validate()
        }
        let effects = access.commandEffects
        system.execute = { world, deltaTime in
            let scope = SystemScope(world: world)
            var transferred = false
            defer {
                scope.isActive = false
                if !transferred {
                    world.reservedCommandIDs.subtract(scope.reservedIDs)
                }
                scope.commands.removeAll()
                scope.reservedIDs.removeAll()
            }
            let context = SystemContext(deltaTime: deltaTime, simulationTime: world.simulationTime)
            try body(context, repeat (each bindings).resolve(scope))
            transferred = true
            return SystemCommandBatch(commands: scope.commands, effects: effects, reservedIDs: scope.reservedIDs)
        }
        return system
    }

    public func onInitialize(_ body: @escaping () -> Void) -> System {
        var system = self
        system.initialize = body
        return system
    }

    public func onCleanup(_ body: @escaping () -> Void) -> System {
        var system = self
        system.cleanup = body
        return system
    }
}

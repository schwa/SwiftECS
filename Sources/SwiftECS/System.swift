public struct System {
    public let id: SystemID
    public private(set) var access = SystemAccess()
    internal var validate: () throws -> Void = {}
    internal var initialize: () -> Void = {}
    internal var cleanup: () -> Void = {}
    internal var execute: (World, Double) throws -> Void = { _, _ in }

    public init(_ id: SystemID) {
        self.id = id
    }

    public func query<each Term: SystemTerm>(_ terms: repeat each Term, matching filter: Query = .all) -> SystemQueryBuilder<repeat each Term> {
        SystemQueryBuilder(system: self, query: SystemQuery(repeat each terms, matching: filter))
    }

    public func run<each Input: SystemInput>(_ inputs: repeat each Input, body: @escaping (SystemContext, repeat (each Input).Value) throws -> Void) -> System {
        var system = self
        var access = SystemAccess()
        repeat access.merge((each inputs).binding.access)
        system.access = access
        system.validate = {
            repeat try (each inputs).binding.validate()
        }
        system.execute = { world, deltaTime in
            let scope = SystemScope(world: world)
            defer {
                scope.isActive = false
                scope.commands.removeAll()
                scope.reservedIDs.removeAll()
            }
            let context = SystemContext(deltaTime: deltaTime, simulationTime: world.simulationTime)
            try body(context, repeat (each inputs).binding.resolve(scope))
            scope.isActive = false
            try scope.flush()
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

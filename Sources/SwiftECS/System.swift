/// A unit of logic that runs over declared inputs.
///
/// Build a system from an ID, then add inputs with `query(_:matching:)` or `run(_:body:)`. Systems are values;
/// each builder method returns a new system.
public struct System {
    /// The system's identifier.
    public let id: SystemID
    /// The reads, writes, queries, and command effects the system declares.
    public private(set) var access = SystemAccess()
    internal var validate: () throws -> Void = {}
    internal var initialize: () -> Void = {}
    internal var cleanup: () -> Void = {}
    internal var execute: (World, Double) throws -> SystemCommandBatch = { _, _ in SystemCommandBatch() }
    internal var prepareParallel: ((World, Double, ParallelIDPool, Int) -> [ParallelJob])?

    /// Whether the system was built with a parallel callback and can run on worker tasks.
    public var isParallelEligible: Bool { prepareParallel != nil }

    /// Creates a system with no inputs.
    public init(_ id: SystemID) {
        self.id = id
    }

    /// Starts a system that runs over one query.
    ///
    /// - Parameters:
    ///   - terms: The component terms, such as ``Read`` and ``Write``. Each component type may appear once.
    ///   - filter: Additional matching conditions.
    /// - Returns: A builder. Finish it with ``SystemQueryBuilder/each(_:)`` or ``SystemQueryBuilder/run(_:)``.
    public func query<each Term: SystemTerm>(_ terms: repeat each Term, matching filter: Query = .all) -> SystemQueryBuilder<repeat each Term> {
        SystemQueryBuilder(system: self, query: SystemQuery(repeat each terms, matching: filter))
    }

    /// Returns a system that calls the body once per run with the resolved inputs.
    ///
    /// Inputs can be queries and command inputs. A system with no inputs still runs once per run.
    public func run<each Input: SystemInput>(_ inputs: repeat each Input, body: @escaping (SystemContext, repeat (each Input).Value) throws -> Void) -> System {
        bind(repeat (each inputs).binding, body: body)
    }

    internal func bind<each Value>(_ bindings: repeat SystemBinding<each Value>, body: @escaping (SystemContext, repeat each Value) throws -> Void) -> System {
        var system = self
        system.prepareParallel = nil
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

    /// Returns a system that calls the body when the system is registered.
    public func onInitialize(_ body: @escaping () -> Void) -> System {
        var system = self
        system.initialize = body
        return system
    }

    /// Returns a system that calls the body once when the system is removed from the world.
    public func onCleanup(_ body: @escaping () -> Void) -> System {
        var system = self
        system.cleanup = body
        return system
    }
}

// Swift 6 capture checking is required, not a Swift 5 compatibility warning.
// swiftlint:disable incompatible_concurrency_annotation
extension System {
    /// Returns a system whose callback can run on a worker task.
    ///
    /// All inputs must be parallel-eligible, and the body must be `@Sendable`.
    public func runParallel<each Input: ParallelSystemInput>(_ inputs: repeat each Input, body: @escaping @Sendable (SystemContext, repeat (each Input).Value) throws -> Void) -> System {
        let bindings = (repeat (each inputs).parallelBinding)
        var system = bind(repeat (each bindings).binding, body: body)
        system.prepareParallel = { world, deltaTime, identities, _ in
            let factories = (repeat (each bindings).prepare(world))
            let context = SystemContext(deltaTime: deltaTime, simulationTime: world.simulationTime)
            let job = ParallelJob(identities: identities) { scope in
                try body(context, repeat (each factories)(scope))
            }
            return [job]
        }
        return system
    }
}
// swiftlint:enable incompatible_concurrency_annotation

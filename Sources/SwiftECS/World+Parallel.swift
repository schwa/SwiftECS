extension World {
    /// Runs the default pipeline with parallel-eligible systems on worker tasks, then advances simulation time.
    ///
    /// - Parameters:
    ///   - deltaTime: The time step, in seconds.
    ///   - parallelism: The maximum number of concurrent worker tasks. Must be positive.
    ///   - isolation: The actor that owns the world.
    /// - Throws: ``SystemError`` for an invalid schedule or parallelism, or an error from a system callback.
    public func update(deltaTime: Double, parallelism: Int, isolation: isolated (any Actor)? = #isolation) async throws {
        try validateParallelRun(parallelism)
        let pipeline = defaultPipeline
        let schedule = try resolveSchedule(pipeline)
        let configuration = ParallelRunConfiguration(deltaTime: deltaTime, advancesTime: true, synchronization: pipeline.synchronization, parallelism: parallelism)
        try await executeParallel(schedule, configuration: configuration, isolation: isolation)
    }

    /// Runs the pipeline with parallel-eligible systems on worker tasks. Does not advance simulation time.
    public func run(_ pipeline: Pipeline, deltaTime: Double, parallelism: Int, isolation: isolated (any Actor)? = #isolation) async throws {
        try validateParallelRun(parallelism)
        let schedule = try resolveSchedule(pipeline)
        let configuration = ParallelRunConfiguration(deltaTime: deltaTime, advancesTime: false, synchronization: pipeline.synchronization, parallelism: parallelism)
        try await executeParallel(schedule, configuration: configuration, isolation: isolation)
    }

    /// Runs one unregistered system, on worker tasks if it is parallel-eligible.
    public func run(_ system: System, deltaTime: Double, parallelism: Int, isolation: isolated (any Actor)? = #isolation) async throws {
        try validateParallelRun(parallelism)
        try system.validate()
        let descriptor = SystemDescriptor(id: system.id, implementation: system, registrationOrder: 0)
        let entry = ScheduledSystem(entityID: EntityID(), descriptor: descriptor, predecessors: [])
        let configuration = ParallelRunConfiguration(deltaTime: deltaTime, advancesTime: false, synchronization: .automatic, parallelism: parallelism)
        try await executeParallel([entry], configuration: configuration, isolation: isolation)
    }

    /// Runs the pipeline stored on the entity with parallel-eligible systems on worker tasks.
    ///
    /// - Throws: ``SystemError/invalidPipeline(_:)`` if the entity has no ``Pipeline``.
    public func run(_ pipeline: Entity, deltaTime: Double, parallelism: Int, isolation: isolated (any Actor)? = #isolation) async throws {
        try validateParallelRun(parallelism)
        try validateRelationshipEntity(pipeline)
        guard let configuration = pipeline[Pipeline.self] else {
            throw SystemError.invalidPipeline(pipeline.id)
        }
        try await run(configuration, deltaTime: deltaTime, parallelism: parallelism, isolation: isolation)
    }

    private func validateParallelRun(_ parallelism: Int) throws {
        guard parallelism > 0 else {
            throw SystemError.invalidParallelism
        }
        guard !parallelRunActive, executions.isEmpty else {
            throw SystemError.parallelRunInProgress
        }
        try Task.checkCancellation()
    }

    private func executeParallel(_ schedule: [ScheduledSystem], configuration: ParallelRunConfiguration, isolation: isolated (any Actor)?) async throws {
        let execution = PipelineExecution()
        beginParallelRun(execution, deltaTime: configuration.deltaTime, advancesTime: configuration.advancesTime)
        defer { endParallelRun(execution) }
        try await execution.runParallel(schedule, in: self, configuration: configuration, isolation: isolation)
    }
}

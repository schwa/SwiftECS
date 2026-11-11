/// Counts and timings from the most recent completed run. Read it from ``World/lastRunStatistics``.
public struct PipelineRunStatistics: Equatable, Sendable {
    /// The number of systems the run attempted.
    public internal(set) var systemCount = 0
    /// The number of nonempty command merges.
    public internal(set) var mergeCount = 0
    /// The number of deferred commands the run attempted.
    public internal(set) var commandCount = 0
    /// The number of batches that ran systems in parallel.
    public internal(set) var parallelBatchCount = 0
    /// The number of worker tasks that parallel batches started.
    public internal(set) var parallelTaskCount = 0

    /// The wall time of the whole run, including schedule resolution.
    public internal(set) var totalDuration: Duration = .zero
    /// The time spent resolving the schedule.
    public internal(set) var resolveDuration: Duration = .zero
    /// The time spent applying deferred commands, summed over all merges.
    public internal(set) var mergeDuration: Duration = .zero
    /// Per-system timings, in the order the systems ran.
    public internal(set) var systemTimings: [SystemTiming] = []
    /// Time spent in parallel batches, by phase.
    public internal(set) var parallelPhases = ParallelPhaseDurations()
}

/// The time one system took in a run.
public struct SystemTiming: Equatable, Sendable {
    /// The system's identifier.
    public let id: SystemID
    /// For a serial system, the callback's wall time. For a parallel system, the preparation time (snapshots and
    /// indexes) plus the summed execution time of its worker jobs.
    public let duration: Duration
    /// Whether the system ran on worker tasks.
    public let ranInParallel: Bool
}

/// Time spent in the phases of parallel batches, summed over all batches in a run.
public struct ParallelPhaseDurations: Equatable, Sendable {
    /// Building jobs on the owning actor, including snapshots and indexes.
    public internal(set) var prepare: Duration = .zero
    /// Wall time from dispatching the jobs until all of them finish.
    public internal(set) var execute: Duration = .zero
    /// Summed time the jobs ran on workers. `execute` minus `workerBusy / parallelism` approximates dispatch and join
    /// overhead.
    public internal(set) var workerBusy: Duration = .zero
    /// Writing worker results back into the world's columns.
    public internal(set) var writeBack: Duration = .zero
}

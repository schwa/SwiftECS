/// Counts from the most recent completed run. Read it from ``World/lastRunStatistics``.
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
}

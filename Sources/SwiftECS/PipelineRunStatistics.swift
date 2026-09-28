public struct PipelineRunStatistics: Equatable, Sendable {
    public internal(set) var systemCount = 0
    public internal(set) var mergeCount = 0
    public internal(set) var commandCount = 0
    public internal(set) var parallelBatchCount = 0
    public internal(set) var parallelTaskCount = 0
}

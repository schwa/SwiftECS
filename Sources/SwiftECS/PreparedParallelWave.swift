internal struct PreparedParallelWave {
    let entries: [ScheduledSystem]
    var jobs: [ParallelJob] = []
    var ranges: [Range<Int>] = []
}

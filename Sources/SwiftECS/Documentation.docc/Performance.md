# Performance

Validation commands, benchmarks, and measured results.

The Survival demo stages retain serial fallback.
Demo UI ticks remain synchronous because their views read the live world. Async UI simulation needs isolated render snapshots, tracked separately in issue #15.

```sh
fish Scripts/check-concurrency.fish
xcb test SwiftECS/SwiftECS -- --sanitize thread
ECS_RUN_PARALLEL_BENCHMARKS=1 xcb test SwiftECS/SwiftECS -c release -- --filter ParallelPerformanceTests
```

The compile checks cover unsafe captures, actor isolation, payloads, unrestricted commands, and escaped write handles.
Tests cover bounded overlap, shared reads, separate-column writes, partitions, deterministic command order, cancellation, observers, ownership, and cleanup.

Release measurements after the profiling fixes on Apple M5 Max, macOS 27.0, Swift 6.4 used 4,096 entities and two runs:

| Workload | Serial ms/frame | Four-job limit ms/frame |
| --- | ---: | ---: |
| Independent compute | 9.67–9.75 | 2.91–3.01 |
| Partitioned compute | 2.44–2.47 | 1.10 |
| Memory-bound | 0.64 | 0.58–0.78 |
| Conflicting systems | 9.63–9.81 | 9.88–10.04 |
| Command-heavy | 16.20–16.27 | 17.02–17.03 |
| Empty callbacks | 0.014–0.016 | 0.41–0.43 |

The benchmark also covers 64 entities and limits of one and two. A limit of one measures the synchronous reference runner.
Parallel execution helps these compute-heavy cases, but can add overhead to small, conflicting, and command-heavy workloads.
The memory-bound case shows little benefit at this size. There is no automatic workload tuning or lock-free World storage claim.

A direct 100,000-entity movement comparison uses the original XYZ arithmetic and three component writes per entity.
Each mode has three warm-up frames, 60 measured frames, and three rotated rounds. Every entity is verified after each sample.

| Movement path | Before profiling fixes | After fixes, ms/frame |
| --- | ---: | ---: |
| Original raw component-reference loop | 17.25 | 14.68 |
| Typed system, serial | 77.28 | 12.50 |
| Typed system, 2 jobs | 153.46 | 10.56 |
| Typed system, 4 jobs | 116.59 | 7.97 |
| Typed system, 8 jobs | 153.46 | 6.45 |

The system modes use the same `.eachParallel` callback, with `Read<Physics>` supplying a value per row.
The raw baseline retains its original component-reference access. Eight jobs are about 1.94 times faster than the corrected typed serial path.
Issues #37 and #38 retain the profiling findings. Generic metadata and exclusivity checks dominated serial access, while the original worker path also contended on column locks.
The fixes bind field access once, specialize iteration over resolved output types, and use task-owned buffers with dirty-only writeback.
Issues #39–#41 track further scaling measurements and overhead.

```sh
ECS_RUN_MOVEMENT_BENCHMARKS=1 xcb test SwiftECS/SwiftECS -c release -- --filter MovementParallelBenchmarkTests
```

The earlier query-access and cost-isolation benchmarks remain available separately:

```sh
ECS_RUN_BENCHMARKS=1 xcb test SwiftECS/SwiftECS -c release -- --filter QueryPerformanceTests
ECS_RUN_BENCHMARKS=1 xcb test SwiftECS/SwiftECS -c release -- --filter TypedQueryCostTests
```

`MovementScalingBenchmarkTests` sweeps job limits and entity counts and reports speedup, parallel efficiency, and the best observed limit:

```sh
ECS_RUN_SCALING_BENCHMARKS=1 xcb test SwiftECS/SwiftECS -c release -- --filter MovementScalingBenchmarkTests
```

`ObservationOverheadBenchmarkTests` isolates storage-observation cost and notification volume from the work, across access styles, observer counts, and substep batching (SwiftUI body/rendering cost is out of scope):

```sh
ECS_RUN_OBSERVATION_BENCHMARKS=1 xcb test SwiftECS/SwiftECS -c release -- --filter ObservationOverheadBenchmarkTests
```

`RelationshipBenchmarkTests` measures deep/broad/DAG construction, reparenting, direct and descendant queries, transitive traversal, and recursive deletion:

```sh
ECS_RUN_RELATIONSHIP_BENCHMARKS=1 xcb test SwiftECS/SwiftECS -c release -- --filter RelationshipBenchmarkTests
```

`ScheduleResolutionBenchmarkTests` isolates schedule construction and ordering (via `executionOrder(for:)`) from callback dispatch, across system/phase counts, chains, wide DAGs, empty phases, and subset pipelines:

```sh
ECS_RUN_SCHEDULE_BENCHMARKS=1 xcb test SwiftECS/SwiftECS -c release -- --filter ScheduleResolutionBenchmarkTests
```

Each run resolves a new schedule with no cache. Resolution time grows faster than linearly (about O(N^2)) with the number of selected systems. Small schedules take less than 1 ms. Schedules with hundreds to thousands of systems take tens of milliseconds. Dependency chains and phase chains that hold systems cost the most. In a run with no work, resolution takes most of the time, not dispatch.

`ParallelPartitionBenchmarkTests` isolates tail latency under skewed per-row work and the parallel dispatch break-even:

```sh
ECS_RUN_PARTITION_BENCHMARKS=1 xcb test SwiftECS/SwiftECS -c release -- --filter ParallelPartitionBenchmarkTests
```

With uneven work, equal fixed partitions make the heaviest range finish last. A `tasksPerWorker` value above one lets the worker pool balance the load. On Apple M5 Max (limit 8, 100k uneven rows), the speedup increased from 3.87x to 5.50x. Frame time decreased from about 31.5 ms to 22.2 ms. Parallel dispatch costs about 0.7 ms per frame. As a result, serial execution is faster below about 16k uniform rows. More partitions help uneven or compute-heavy work. They do not help small or memory-bound work.

`ParallelBufferBenchmarkTests` isolates snapshot copy, dirty-mask, and writeback costs across component size, write density, archetype count, and job count:

```sh
ECS_RUN_BUFFER_BENCHMARKS=1 xcb test SwiftECS/SwiftECS -c release -- --filter ParallelBufferBenchmarkTests
```

Workers copy the whole column once and then copy their partition slice. After the join, they write changed values back. These three copies cost little for small components, and parallel is still faster than serial. For large components, serial in-place writes are faster. At 200k rows, a 64-byte component took 9.6 ms parallel and 8.9 ms serial. An 8-byte component took 7.9 ms parallel and 8.9 ms serial. Because only changed values are written back, sparse writes stay fast. A copy per partition directly from the live column can remove the whole-column copy. This change is the next step for large components.

Acyclic chain construction is quadratic (a cycle check walks toward the root before each link), so deep hierarchies are the costly case. Descendant-predicate queries evaluate per candidate and cost far more than a single breadth-first traversal from the root. Registered and unregistered direct-child queries measure the same, because registration caches archetypes, not relationship matches.

Storage observation publishes once per frame for any number of observers. The world notifies each armed observer once, and each observer reads its value again. On the fast typed path, this repeated read has a measurable cost as the observer count increases. Compared with slower entity-handle work, the cost is very small.

Movement is memory-bandwidth bound. On Apple M5 Max (18 processors, macOS 27.0, Swift 6.4, Release), light movement scaled to about 1.26x at 18 jobs for 100,000 entities.
One million entities peaked near 1.89x at four jobs and regressed beyond it. Raising per-entity work (`ECS_SCALING_ITERATIONS=200`) reached about 2.11x at 16 jobs.
Parallel efficiency decreases as the job count increases. More jobs do not give a linear speedup. Phase-level timing (dispatch, join, writeback, merge) needs core instrumentation and is tracked in #40 and #41.
Override the sweep with `ECS_SCALING_ENTITIES`, `ECS_SCALING_LIMITS`, `ECS_SCALING_ROUNDS`, `ECS_SCALING_FRAMES`, and `ECS_SCALING_ITERATIONS`.


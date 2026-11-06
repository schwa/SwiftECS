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

Each run resolves a fresh schedule with no cache. Resolution is superlinear (about O(N^2)) in the selected system count: sub-millisecond for typical small schedules, but tens of milliseconds once schedules reach hundreds to thousands of systems. Dependency chains and system-bearing phase chains cost the most; a no-op run is dominated by resolution, not dispatch.

`ParallelPartitionBenchmarkTests` isolates tail latency under skewed per-row work and the parallel dispatch break-even:

```sh
ECS_RUN_PARTITION_BENCHMARKS=1 xcb test SwiftECS/SwiftECS -c release -- --filter ParallelPartitionBenchmarkTests
```

With skewed work, fixed equal partitions leave the heaviest range as a straggler; over-decomposition (`tasksPerWorker` above one) lets the bounded pool load-balance. On Apple M5 Max (limit 8, 100k skewed rows) it improved 3.87x to 5.50x speedup, cutting frame time from about 31.5 to 22.2 ms. Parallel dispatch has a fixed floor near 0.7 ms per frame, so serial wins below roughly 16k uniform rows; over-decomposition helps skewed or compute-heavy work, not small or purely memory-bound work.

`ParallelBufferBenchmarkTests` isolates snapshot copy, dirty-mask, and writeback costs across component size, write density, archetype count, and job count:

```sh
ECS_RUN_BUFFER_BENCHMARKS=1 xcb test SwiftECS/SwiftECS -c release -- --filter ParallelBufferBenchmarkTests
```

Workers snapshot the whole column once, copy their partition slice, then write dirty values back after joining. That triple-copy is cheap for small components (parallel still beats serial) but makes large components regress against serial in-place writes: at 200k rows a 64-byte component measured 9.6 ms parallel versus 8.9 ms serial, while an 8-byte component measured 7.9 ms versus 8.9 ms. Dirty-only writeback keeps sparse writes cheap. Removing the redundant whole-column snapshot (a bulk per-partition copy from the live column) is the identified follow-up for large-component workloads.

Acyclic chain construction is quadratic (a cycle check walks toward the root before each link), so deep hierarchies are the costly case. Descendant-predicate queries evaluate per candidate and cost far more than a single breadth-first traversal from the root. Registered and unregistered direct-child queries measure the same, because registration caches archetypes, not relationship matches.

Storage observation publishes once per frame regardless of observer count; each armed observer is notified once and recomputes its read (world-wide invalidation). On the fast typed path this per-observer recompute is measurable as observer count rises, while it is negligible against heavier entity-handle work.

Movement is memory-bandwidth bound. On Apple M5 Max (18 processors, macOS 27.0, Swift 6.4, Release), light movement scaled to about 1.26x at 18 jobs for 100,000 entities.
One million entities peaked near 1.89x at four jobs and regressed beyond it. Raising per-entity work (`ECS_SCALING_ITERATIONS=200`) reached about 2.11x at 16 jobs.
Parallel efficiency falls as jobs increase; more jobs do not approach linear speedup. Phase-level timing (dispatch, join, writeback, merge) needs core instrumentation and is tracked in #40 and #41.
Override the sweep with `ECS_SCALING_ENTITIES`, `ECS_SCALING_LIMITS`, `ECS_SCALING_ROUNDS`, `ECS_SCALING_FRAMES`, and `ECS_SCALING_ITERATIONS`.


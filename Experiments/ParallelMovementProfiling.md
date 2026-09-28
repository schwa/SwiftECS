# Movement profiling: issues #37 and #38

Environment: Apple M5 Max (18 processors), macOS 27.0, Swift 6.4, Release builds.

## Reproduction

```fish
ECS_RUN_MOVEMENT_BENCHMARKS=1 xcb test SwiftECS/SwiftECS -c release -- --filter MovementParallelBenchmarkTests
fish Scripts/profile-movement.fish 1 600 6
fish Scripts/profile-movement.fish 4 1600 6
```

The benchmark runs 100,000 entities with three warm-up frames and 60 measured frames. It rotates five modes across three rounds.
The XYZ movement math and three component writes per entity are unchanged. Every sample verifies all transforms and velocities.
The raw loop retains its original component-reference access. Typed systems read Physics as a value once per row.

The profiler script waits for a PID file written after warm-up, then attaches `sample` to that process. No startup delay is assumed.
Profiles and run logs remain in the printed `/tmp/swiftecs-profile.*` directory. Profiled timings are not used for benchmark comparisons.

## Evidence before changes

The serial profile contained 5,946 main-thread samples, with 5,743 beneath the movement update.
Generic and tuple metadata operations dominated the hot loop: `getCache`, generic context lookup, metadata-key comparison, and tuple-cache lookup.
The stack entered these functions from `SystemRowIterator.next`, term resolution, and component access.

The four-job profile also showed column-lock contention beneath `ParallelTaskState.read`:

- `__ulock_wait2`: 1,931 top-of-stack samples.
- `__ulock_wake`: 718 samples.
- Generic tuple-cache insertion/lookup: 1,969 samples.

These are sampled stacks across threads, not percentages of frame time.

After initial specialization, generic metadata costs decreased. Repeated dynamic exclusivity checks on owner-local state became a prominent remaining cost.

## Changes

- Bind accessors once per column rather than construct generic component access paths per row.
- Run iteration over resolved output types. `SystemRow<Terms...>` and `SystemRows<Terms...>` retain explicit term syntax through type aliases.
- Make the hot iteration and access paths available for cross-module specialization.
- Keep lifetime and structural-revision checks, using non-Sendable owner-local cells to avoid repeated dynamic exclusivity bookkeeping.
- Give each worker task its own mutable component buffers. Partitions copy only their selected rows.
- Share buffers across overlapping queries within one task, preserving read-after-write behavior.
- Apply dirty values after all jobs join, before dependent systems and structural merges. Apply edits from failed jobs too, preserving the no-rollback contract.
- Keep World storage locks at snapshot/writeback boundaries. Worker element access no longer takes column or bookkeeping locks.

Owner-local cells manage initialized memory and never expose pointers through the public API. They are not Sendable.
Only immutable value updates cross back to the owner. No new unchecked-Sendable wrapper was added for these buffers or cells.

## Results

Unprofiled three-round medians, milliseconds per frame:

| Path | Before | After |
| --- | ---: | ---: |
| Raw component-reference loop | 17.25 | 14.68 |
| Typed system, serial | 77.28 | 12.50 |
| Typed system, 2 jobs | 153.46 | 10.56 |
| Typed system, 4 jobs | 116.59 | 7.97 |
| Typed system, 8 jobs | 153.46 | 6.45 |

The four-job path is about 14.6 times faster than its previous implementation, and 1.57 times faster than the corrected typed serial path.
Eight jobs are about 1.94 times faster than corrected typed serial execution.

The post-change four-job profile no longer has element-lock waits among its hot stacks. Remaining costs include reference counting, array operations, buffer preparation, and iteration.
Snapshots and writeback still cost memory bandwidth. These results do not imply linear scaling or a benefit for every workload.

## Verification

Coverage includes filtered and uneven partitions, overlapping queries, dirty-only writeback, failed callbacks, cancellation, deterministic command order, and owner-cell lifetime.
Run the regular suite, Thread Sanitizer, and the compile checks after changes:

```fish
xcb test SwiftECS/SwiftECS
xcb test SwiftECS/SwiftECS -c release -- --sanitize thread
fish Scripts/check-concurrency.fish
```

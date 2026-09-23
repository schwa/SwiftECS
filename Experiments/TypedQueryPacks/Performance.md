# Query access measurements

Umbrella issue: #14. Remaining investigations: #13 (row access), #5 (observation), and #4 (substep batching).

The latest experiment trace is `~/Desktop/ECS-Profiles/typed-query-column-inline.trace`. The directory contains logs, analysis, provenance notes, and a patch identifying the tested changes. The previous baseline is `typed-query-0ab9af6b.trace`. Both captures include all processes and need review before sharing.

## Setup

- Apple M5 Max, 128 GB memory, macOS 27.0 (26A428).
- Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), Release configuration.
- 100,000 entities in one archetype, each with `Transform` and `Physics`.
- Each update reads both components once, advances three position fields, and writes both components.
- All access paths run inside `world.update()` and use a registered query.
- Each sample uses a fresh world, two warm-up updates, and ten measured updates. Setup and result checks are outside the timer.
- Three rounds run serially. The access-path order rotates between rounds.

The observed case has one synchronous observer that reads entityCount and registers again after each notification. It receives one notification per update.

No component-event handlers are registered. This is not a SwiftUI rendering benchmark.

## Results

Milliseconds per update, across three samples:

| Access | Storage observer | Median | Min | Max |
|---|---|---:|---:|---:|
| Entity handles | No | 309.467 | 308.261 | 311.928 |
| Fast references | No | 198.465 | 195.566 | 223.130 |
| Typed queries | No | 111.405 | 111.023 | 111.781 |
| Entity handles | Yes | 308.544 | 305.958 | 309.508 |
| Fast references | Yes | 195.485 | 193.887 | 198.902 |
| Typed queries | Yes | 112.347 | 111.314 | 113.361 |

Without an active observer, typed queries take 44% less time than fast references and 64% less time than entity handles.

An active observer adds no clear large cost in this run. Small differences overlap ordinary run variation. Both cases still include the library observation machinery.

Typed queries still exceed the 16.7 ms budget for 60 updates per second at this entity count. These measurements do not isolate the remaining costs.

This workload writes unchanged physics values to keep component writes comparable. It does not establish results for read-only queries, many archetypes, or component-event handlers.

## Time Profiler findings

A Release run under Time Profiler reproduced approximately 112 ms per typed-query update. The trace is `/tmp/ecs-query-profile.trace`.

The analysis selects samples with `QueryBenchmarkSystem.update` and either `TypedEntityRef` or `TypedQueryIterator` in the stack. This excludes setup and verification, but includes warm-up updates. It combines the observed and unobserved cases. Selected CPU sample weight is 7.766 seconds.

Inclusive sample weights overlap and must not be added:

| Call path | Selected sample weight |
|---|---:|
| `TypedEntityRef.set` | 66.3% |
| `ObserverRegistry.notifyChanged` | 52.2% |
| `ComponentType.init` | 51.5% |
| `String.init(describing:)` | 48.8% |
| Generic metadata lookup (`_swift_getGenericMetadata`) | 29.1% |
| `TypedQueryIterator.next` | 28.3% |
| `Array.subscript.modify` | 8.3% |
| `TypedEntityRef.values.getter` | 5.3% |

The largest identified cost is component-event dispatch without handlers. Every write constructs a `ComponentType`, including its debug name through `String(describing:)`, before the registry checks for handlers.

Sample stacks show string conversion, reflection, dynamic casts, and protocol-conformance checks beneath this path. Typed references removed dictionary access from column reads, but component notification still constructs type metadata for each write.

Iterator construction also incurs generic metadata and reference-management work per row. These costs warrant investigation after the component-event path. The samples do not establish that array storage is the primary bottleneck.

No optimization changes were made during the initial profile.

## After issue #11

Observer dispatch now uses `ObjectIdentifier` keys and returns early when the registry is empty. Removing the last handler also removes its registry bucket.

The same Release benchmark under Time Profiler produced these medians:

| Access | Without storage observer | With storage observer |
|---|---:|---:|
| Entity handles | 255.000 ms | 251.961 ms |
| Fast references | 142.348 ms | 142.878 ms |
| Typed queries | 54.070 ms | 54.199 ms |

Typed-query time fell about 51% from the initial 111.405 ms median. The unchanged profiling baseline was approximately 112 ms.

The new trace is `/tmp/ecs-issue-11-profile.trace`. With the same stack filter, selected CPU sample weight is 3.621 seconds:

- `ObserverRegistry.notifyChanged`: 0.9% inclusive, down from 52.2%.
- `TypedQueryIterator.next`: 59.9% inclusive.
- `TypedEntityRef.set`: 28.4% inclusive.
- Generic metadata lookup: 24.4% inclusive.
- `Array.subscript.modify`: 17.3% inclusive.

These percentages overlap. Type-name construction no longer appears in the selected stacks. Iterator advancement is now the largest remaining path.

The benchmark still has no component-event handlers. Regression tests cover event delivery, handler removal, registration after removal, distinct type identities, and batched storage invalidation.

## Iterator and row-cost isolation

A separate opt-in test uses the same entity count and components. Each phase runs three times with a rotated order, two warm-up updates, and ten measured updates. Worlds are fresh, with no observers or structural changes during measurement.

| Phase | Median | Sample range |
|---|---:|---:|
| 1,000 typed-query constructions | 1.864 ms | 1.860–1.948 ms |
| Fresh iteration, entity ID checksum only | 31.715 ms | 31.694–32.246 ms |
| Fresh iteration, component reads | 38.321 ms | 37.621–40.407 ms |
| Fresh iteration, component reads and writes | 56.309 ms | 53.913–56.783 ms |
| Pre-collected rows, component reads | 6.102 ms | 6.029–6.110 ms |
| Pre-collected rows, component reads and writes | 22.013 ms | 21.980–23.293 ms |

Query construction costs about 1.9 microseconds per call in this single-archetype case. It cannot explain the update cost.

Pre-collecting rows excludes typed iterator advancement and row construction from the timer. It does not remove row copies during array iteration. This isolates costs, not a safe general caching policy. Retained rows remain unsafe across structural changes.

The approximately 32 ms difference between fresh and retained reads agrees with the iterator profile. The remaining read/write work also exceeds a 16.7 ms frame budget in this workload.

The existing profile places generic metadata work beneath iterator advancement and array modification. It does not prove that copy-on-write copies entire arrays or that spans will solve the remaining cost. The profiler label `Swift runtime failure: Variadic generic index out of bounds` is not evidence of a runtime failure: these runs complete successfully.

Run the isolation test from the repository root:

```sh
env ECS_RUN_BENCHMARKS=1 xcb test "$PWD/Package.swift/ECS" -c Release -- --filter TypedQueryCostTests
```

## After issue #12

Typed rows now hold one shared typed-storage reference instead of their own column tuple. Iterator advancement passes that reference without a pack expansion. The public API is unchanged.

The same isolation test produced these medians:

| Phase | Before | After |
|---|---:|---:|
| Iterator plus identity checksum | 31.715 ms | 2.868 ms |
| Fresh reads | 38.321 ms | 9.198 ms |
| Fresh reads and writes | 56.309 ms | 24.726 ms |
| Retained reads | 6.102 ms | 6.193 ms |
| Retained reads and writes | 22.013 ms | 21.891 ms |

Iterator-only time fell about 91%. The retained-row costs stayed similar. This supports the iterator diagnosis rather than a transfer of cost into reads or writes.

The full comparison under Time Profiler measured 25.250 ms/update without a storage observer and 25.502 ms with one. Entity handles measured 255.067 ms and fast references measured 138.202 ms without observers.

Trace: `~/Desktop/ECS-Profiles/typed-query-0ab9af6b.trace`. With the same stack filter, selected sample weight is 1.621 seconds. Iterator advancement now accounts for 9.7% inclusive, down from 59.9%.

The setter accounts for 67.3% inclusive, including array modification and generic metadata work. These overlapping costs remain under #13. This workload still exceeds the 16.7 ms budget.

## Write-helper experiment (#13)

Moving `column.data[index] = value` into a generic helper did not produce a useful improvement. Preventing helper inlining made the measured workload slower.

The same Release isolation benchmark, three samples per variant:

| Variant | Fresh read/write median | Retained read/write median |
|---|---:|---:|
| Existing inline array write | 24.726 ms | 21.891 ms |
| Generic write helper | 24.619 ms | 21.658 ms |
| Helper with `@inline(never)` | 25.447 ms | 22.439 ms |

The ordinary helper difference is too small to establish a benefit across separate runs. The experiment does not establish whether array storage or specialization is the underlying problem.

Both helper variants were removed. Production code remains unchanged, and #13 remains open.

## Cross-module specialization experiment (#13)

Further variants produced these Release isolation medians for fresh reads and writes:

| Variant | Median |
|---|---:|
| Baseline after #12 | 24.726 ms |
| Non-inlined setter on Column | 24.175 ms |
| Column setter with scoped mutable buffer access | 22.681 ms |
| ContiguousArray column storage | 22.742 ms |
| Inlinable typed accessors, original Array storage | 15.069 ms |

The first three variants were removed. The retained change marks typed row accessors as `@inlinable`, with the required internal declarations marked `@usableFromInline`. This exposes implementation details to client compilation but adds no public methods. Internal representation changes now require care because compiled clients can embed these accessor bodies.

Core and demo tests pass. Event delivery and storage observation remain active. The retained-row read/write median falls to 11.626 ms, and fresh reads fall to 4.795 ms.

The mixed comparison under Time Profiler measured 16.548 ms/update without a storage observer and 16.731 ms with one. Other paths also ran slower than earlier captures, so these separate runs do not isolate compiler changes from machine variation.

A longer typed-only capture used 100 measured updates per sample. It measured 14.987 ms without an observer and 15.003 ms with one. This is near the simulation budget, not evidence of rendering headroom or steady 60 Hz performance.

Trace: `~/Desktop/ECS-Profiles/typed-query-inline-experiment.trace`. The stack filter now selects `QueryBenchmarkSystem.update` because inlining removes some typed-accessor frames. The benchmark contains only the typed access path. Selected CPU weight is 8.962 seconds, including warm-up updates and both observer cases.

Inclusive costs still overlap: specialized setter 59.3%, generic metadata lookup 40.7%, iterator advancement 16.0%, and specialized getter 12.6%. Metadata work remains significant. Issue #13 remains open.

The benchmark now accepts optional `ECS_BENCHMARK_ACCESS` and `ECS_BENCHMARK_FRAMES` overrides. Defaults remain all access paths and ten measured updates.

```sh
env ECS_RUN_BENCHMARKS=1 ECS_BENCHMARK_ACCESS=typed ECS_BENCHMARK_FRAMES=100 xcb test "$PWD/Package.swift/ECS" -c Release -- --filter QueryPerformanceTests
```

## Iterator specialization

Making `TypedQueryIterator.next` and the row initializer inlinable reduces the remaining iterator cost. Required state becomes `@usableFromInline`. No public signatures change.

Release isolation medians:

| Phase | Before | After |
|---|---:|---:|
| Iterator plus identity checksum | 2.851 ms | 0.789 ms |
| Fresh reads | 4.795 ms | 2.657 ms |
| Fresh reads and writes | 15.069 ms | 12.537 ms |
| Retained reads and writes | 11.626 ms | 11.464 ms |

The longer typed-only profile measures 13.418 ms/update without a storage observer and 13.496 ms with one. Each median covers three samples of 100 updates. These numbers leave approximately 3 ms before the 16.7 ms budget, not a guarantee about app rendering.

Trace: `~/Desktop/ECS-Profiles/typed-query-iterator-inline.trace`. With the typed-only update filter, selected CPU weight is 7.821 seconds. Inclusive shares: setter 73.3%, generic metadata lookup 40.7%, getter 13.6%, iterator advancement 4.0%. These overlap.

The latest profile, benchmark log, summary, and patch against `beb20431` are preserved together. Debug/Release tests, macOS demo build/tests, and strict lint pass. Remaining setter and metadata work stays under #13.

## Inlinable column setter

The earlier column-method experiment preceded cross-module specialization. Retesting an `@inlinable Column.setValue` method now produces a useful improvement. The row setter delegates each write to this method. Storage remains Array, and observation and component events remain unchanged.

Isolation medians: fresh read/write 10.319 ms, retained read/write 9.305 ms. The preceding iterator-specialized measurements were 12.537 ms and 11.464 ms respectively.

Back-to-back longer runs use three 100-update samples for each observer case:

| Variant | Without storage observer | With storage observer |
|---|---:|---:|
| Direct array write (baseline) | 13.668 ms | 13.679 ms |
| Inlinable column setter | 9.951 ms | 9.971 ms |

The candidate ran under Time Profiler. Its unobserved samples range from 9.947 to 10.052 ms. These runs establish a useful gain, not a general guarantee for other workloads.

Trace: `~/Desktop/ECS-Profiles/typed-query-column-inline.trace`. Selected typed-only update sample weight is 5.691 seconds. Inclusive shares: row setter 72.5%, column setter 54.3%, generic metadata lookup 28.8%, getter 18.2%, iterator 4.7%. These overlap.

The profile directory contains baseline/candidate logs, summary, and a production patch against `1ff4b5db`. Debug/Release and demo tests, macOS build, and lint pass. No public signature changes.

## Reproduce

Run from the repository root:

```sh
env ECS_RUN_BENCHMARKS=1 xcb test "$PWD/Package.swift/ECS" -c Release -- --filter QueryPerformanceTests
```

The comparison is separate from the stress suite and skips by default. Issue #5 still covers broader observation and SwiftUI measurements.

# Query access measurements

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

## Reproduce

Run from the repository root:

```sh
env ECS_RUN_BENCHMARKS=1 xcb test "$PWD/Package.swift/ECS" -c Release -- --filter QueryPerformanceTests
```

The comparison is separate from the stress suite and skips by default. Issue #5 still covers broader observation and SwiftUI measurements.

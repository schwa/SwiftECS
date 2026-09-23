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

No optimization changes were made during this profile. This identifies candidates, not the speedup that any proposed change will achieve.

## Reproduce

Run from the repository root:

```sh
env ECS_RUN_BENCHMARKS=1 xcb test "$PWD/Package.swift/ECS" -c Release -- --filter QueryPerformanceTests
```

The comparison is separate from the stress suite and skips by default. Issue #5 still covers broader observation and SwiftUI measurements.

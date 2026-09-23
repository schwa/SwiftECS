# ECS

Our Swift entity-component-system experiment. No customers or stable API yet.

## Layout

- `Sources/ECS/`: archetype storage, entities, queries, systems, and observation.
- `Tests/ECSTests/`: unit tests and opt-in stress tests.
- `Demos/SwiftECSDemos/`: SwiftUI arcade with a launch picker, Starfall, and the emoji-based Midnight Survivors. Current validation targets macOS.
- `ISSUES.md`: open work and unresolved design questions.
- `RFCs/`: design proposals.

## Design notes

Entities with the same component types share an archetype. Each component type has its own storage column.

Component additions and removals move entities between archetypes. Creation with all initial components avoids intermediate archetypes. Empty archetypes remain allocated.

Registered queries cache matching archetypes. New archetypes invalidate the cache. The older `EntityRef` still uses a dictionary lookup and cast for each component access.

`typedQuery` binds typed columns once per matching archetype. Rows expose a read-only `values` tuple and a variadic `set` method. Component types must be distinct.

The optional `matching` predicate restricts results further and supports registered queries. An empty component pack selects entities without component requirements.

`set` writes every supplied component and emits an event for each, including unchanged values. It emits one storage invalidation outside updates. Initial performance measurements are in `Experiments/TypedQueryPacks/Performance.md`.

Lazy query sequences retain their selected archetypes. Query references are not safe across structural changes. The typed API has the same restriction.

Structural changes during iteration are unsupported. This includes entity creation, deletion, and component additions or removals from event handlers.

Typed relationships use separate forward/reverse indexes. `ChildOf` enforces one parent and rejects cycles. Ordinary deletion detaches children; explicit recursive deletion removes a subtree.

Relationship queries filter live links after archetype matching. Decisions and examples are in `Experiments/Relationships.md`.

Systems declare dependencies for execution order. `World.update()` advances `simulationTime` before it runs systems.

## Observation

Storage reads establish world-wide observation dependencies, including missing components and empty queries.

During an update, writes only mark storage dirty. The outermost update emits one storage invalidation on exit. Updates without storage changes emit none.

Writes outside an update notify immediately. Sequential simulation substeps each emit their own invalidation. `simulationTime` has separate observation.

Component-event observers still receive individual events, including writes through fast query references. Internal mutations of reference-type components bypass ECS observation.

World replacement must remain observable in app models. Starfall no longer needs a frame counter to trigger redraws.

`World` is not thread-safe. SwiftUI-owned worlds stay on the main actor. The library does not enforce actor isolation.

## Local checks

Run from the repository root:

```sh
swiftlint --strict --quiet
xcb build "$PWD/Package.swift/ECS"
xcb test "$PWD/Package.swift/ECS"
```

Stress tests are opt-in and run serially:

```sh
env ECS_RUN_STRESS_TESTS=1 xcb test "$PWD/Package.swift/ECS" -c Release -- --filter StressTests
```

The query comparison is also opt-in:

```sh
env ECS_RUN_BENCHMARKS=1 xcb test "$PWD/Package.swift/ECS" -c Release -- --filter QueryPerformanceTests
```

Old performance figures came from different iteration APIs. Current measurements cover one workload, not general performance.

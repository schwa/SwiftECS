# ECS

Our Swift entity-component-system experiment. No customers or stable API yet.

## Layout

- `Sources/ECS/`: archetype storage, entities, queries, systems, and observation.
- `Tests/ECSTests/`: unit tests and opt-in stress tests.
- `Demos/Starfall/`: SwiftUI game that exercises the library. Current validation targets macOS.
- `ISSUES.md`: open work and unresolved design questions.
- `RFCs/`: design proposals.

## Design notes

Entities with the same component types share an archetype. Each component type has its own storage column.

Component additions and removals move entities between archetypes. Creation with all initial components avoids intermediate archetypes. Empty archetypes remain allocated.

Registered queries cache matching archetypes. New archetypes invalidate the cache. Fast query references still use a dictionary lookup and cast for each component access.

Lazy query sequences retain their selected archetypes. Query references are not safe across structural changes.

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

Old performance figures came from different iteration APIs. We need fresh measurements before we make performance claims.

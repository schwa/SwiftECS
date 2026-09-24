# ECS-backed phases and pipelines

Implemented for issue #17. This replaces the earlier recommendation to retain scheduler-private dependencies.

## Representation

- A phase is an entity with a `Phase` component.
- A registered system is an entity with a `SystemDescriptor` component.
- `InPhase` assigns each system to one phase. The relationship is exclusive.
- `DependsOn` stores phase-to-phase and system-to-system ordering constraints.
- A `Pipeline` contains a normal `Query`. It can also be a component on a pipeline entity.

`addSystem` returns the system entity. Callers can attach tags and change its relationships through normal ECS APIs.
`SystemDescriptor` is registration metadata managed by `World`. Callers must not copy, replace, or remove this component directly.

Registration without an explicit phase uses a lazily created `Update` phase.
There is no fixed list of engine phases. Applications create the phases they need.

The existing `dependencies:` parameter and the new `before:` and `after:` parameters create `DependsOn` relationships.
Forward references create unregistered system entities. Later registration reuses those entities.
`systemCount` excludes these unresolved references.

## Ordering and errors

Each run selects registered systems through its query and resolves a fresh schedule.
The resolver combines explicit system dependencies with transitive phase dependencies, including paths through empty phases.
Every selected system in a predecessor phase runs before systems in its successor phases.
Among ready systems, registration order breaks ties. Query storage order has no effect.

Relationship traversal remains breadth-first. The scheduler uses a separate topological pass because breadth-first traversal cannot order arbitrary dependency graphs.
`DependsOn` permits cycles during editing. Schedule validation rejects reachable phase cycles and combined system/phase cycles before execution.

An explicit dependency must name a registered, selected system. Missing registrations and excluded dependencies produce distinct errors.
Phase dependencies impose ordering without selecting additional systems. Unrelated invalid systems and phases do not block a valid pipeline.
Missing phase membership, invalid phase components, and invalid dependency targets also produce errors.

Validation completes before any system runs or simulation time advances.
`systemExecutionOrder` now throws rather than silently returning an old schedule after a validation error.
Cycle errors for systems include blocked systems, which can include dependents outside the cycle itself.

## Runtime changes and lifecycle

Each run retains a snapshot of the selected implementations and their execution order.
Tag changes, relationship changes, registrations, and removals affect the next run, not the current snapshot.
A nested run gets its own snapshot. Applications must prevent unbounded recursive execution.

Destroying a system entity removes its registration and calls `cleanup` once.
During execution, cleanup waits until the outermost run finishes, so retained systems never run after cleanup.
`removeAllSystems` removes registered systems and unresolved references. It preserves phase and pipeline entities.
System entities cannot be cloned. `clone` returns `nil` for these entities.

Entity deletion retains the relationship layer's existing rules: deletion removes all incident edges.
Deleting a dependency therefore removes that ordering constraint. Deleting a system's phase leaves missing membership, which fails validation.

## Entry points and observation

`update(deltaTime:)` runs `world.defaultPipeline` and advances simulation time once after validation.
The default pipeline selects all registered systems. Assigning a new value selects a different pipeline for later updates.

`run(_:deltaTime:)` accepts a pipeline value or a pipeline entity. It does not advance simulation time.
This permits independent service pipelines without advancing the gameplay clock.
Pause/resume remains application policy, outside the scheduler.

System, phase, and pipeline entities appear in normal queries, entity counts, and world statistics.
Scheduling metadata uses the normal storage observation mechanism. Registration and removal invalidate observable system counts.
Each run forms one mutation batch. Nested runs publish storage invalidation only after the outermost batch completes.
Component callbacks retain the normal synchronous ECS behavior.

## Cost and trade-offs

The ECS model makes scheduling data queryable and permits independent query-selected pipelines.
It also adds entities and component types to world statistics. Existing code that assumes only application entities needs narrower queries.

Order resolution currently runs for every execution and order inspection. There is no cached schedule to invalidate.
The resolver materializes phase-implied system edges, so large schedules can require quadratic work and storage.
This favors correct runtime edits over an unmeasured cache optimization. A later cache needs to track query membership and both relationship types.

## Verification

`PipelineTests.swift` covers unequal phase paths, empty phases, registration-order ties, subset errors, runtime edits, snapshot removal, lifecycle, and observation.
The existing dependency, nested-update, component-event, and query tests also pass with the ECS-backed representation.

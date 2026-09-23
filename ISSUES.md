# ISSUES.md

---

## 1: Component mutations do not directly invalidate SwiftUI views

+++
status: closed
priority: high
kind: enhancement
created: 2026-09-23T17:28:58Z
updated: 2026-09-23T17:50:27Z
closed: 2026-09-23T17:50:27Z
+++

## Problem
World component storage is excluded from Swift Observation. SwiftUI consumers cannot reliably observe component reads, query membership, or entity lifetime. Starfall maintains a separate frame counter to redraw after simulation updates and player input. Reading simulationTime does not cover mutations outside updates.

## Agreed design
Make world-level observation a library guarantee. Consumers read the existing ECS API without revision counters, manual subscriptions, or simulationTime dependencies. Coarse invalidation is acceptable: a mutation may invalidate every observer reading that world. Keep the invalidation mechanism private so finer-grained tracking can be introduced later without app changes.

## Stage 1: Read and mutation coverage
Register observation dependencies for component reads, component presence/type enumeration, all-components access, entity lookup/existence/count/enumeration, and query results. Cover ordinary, registered, and fast query paths and query-reference component access. Reads returning nil, false, zero, or empty results must also register dependencies.

Invalidate for successful ECS-mediated component writes, additions and removals, entity creation, cloning and destruction, and writes through query references. Audit every public read and mutation path rather than relying on component event callbacks alone. Mutations outside world.update must notify synchronously without requiring a later frame or update call. Preserve existing component-event behavior.

Tests: use withObservationTracking to cover each read/mutation path, missing components becoming present, empty queries gaining matches, queries losing matches, entity destruction, clone/create visibility, and isolation between separate worlds. Rearm observation between assertions because tracking callbacks are one-shot. Do not promise equality suppression for components that are not Equatable; failed operations that change nothing should not invalidate.

## Stage 2: Simulation update batching
Coalesce storage invalidation across one outermost world.update call into one observation notification. Consumers must not receive an intermediate notification for every component write. Mutations outside an update must remain immediately observable. Honor Swift Observation access/willSet/didSet semantics; do not assume an onChange callback is a post-mutation snapshot callback. Deferred UI reads after update returns must see the completed state.

Batch bookkeeping must remain correct on every exit, including thrown errors. Publish pending changes if an update exits after mutation; leave subsequent writes observable. Define and test reentrant/nested update handling so it cannot flush an outer batch early or strand pending invalidation. Keep simulationTime observation working independently; the once-per-update guarantee applies to storage invalidation, not the combined notifications of all separately observed properties.

Tests: multiple writes and mixed structural changes in an update, no storage changes, mutations before/after updates, error cleanup, and supported or explicitly rejected reentrancy. Verify batching using a rearming observer so a one-shot callback cannot hide repeated invalidations.

## Stage 3: Starfall integration and documentation
Remove GameSession.frame and the corresponding Canvas dependency. Verify rendering follows ECS reads for movement, spawning, collection/destruction, and steering between simulation updates. Also verify restart replaces the observed world correctly: world replacement is application state and must itself be observable rather than remaining ObservationIgnored. Add regression coverage for replacement and pause/resume, and manually check the macOS game.

Document the observation contract, coarse invalidation, batching behavior, and ownership/threading requirements. Build and run unit tests after each stage; build the macOS demo for integration. iOS validation is out of scope for this work.

## Boundaries
Guarantee ECS-mediated mutations, not arbitrary internal mutations of reference-type components. Mutating a referenced object without an ECS write is outside this contract. This work does not make World thread-safe or require a new MainActor restriction on the core ECS. Do not introduce asynchronous delivery or timing delays to mask invalidation problems. Per-entity/component granularity and a new public transaction API are not required.

## Completion criteria
All public read/write paths are accounted for in tests, update batching obeys the observation contract, and Starfall renders correctly with no frame counter or simulationTime workaround.

- `2026-09-23T17:50:27Z`: Implemented world-wide storage observation, outermost-update batching, mutation/read coverage, and Starfall integration without a frame counter. Tests cover 10,000 writes producing one invalidation, nested/error paths, empty queries, and world replacement. Default tests pass; stress tests are now opt-in. macOS gameplay manually verified by user. Follow-ups: #4 and #5.

---

## 2: System execution order does not preserve registration order

+++
status: closed
priority: medium
kind: task
labels: effort:xs
created: 2026-09-23T17:28:58Z
updated: 2026-09-23T18:01:44Z
closed: 2026-09-23T18:01:44Z
+++

Independent systems do not execute in registration order. World rebuilds its execution order from dictionary keys, so registering spawn, movement, and collision in that sequence does not establish that sequence at runtime. The Starfall demo must declare explicit dependencies for each stage. This is surprising for small sequential simulations, where registration order might otherwise be assumed to determine execution.

- `2026-09-23T18:01:44Z`: Triage correction: systems uses OrderedDictionary, not an unordered dictionary. rebuildSystemOrder seeds independent systems in registration order. Dependencies can reorder execution. The original report was inaccurate; closing as invalid with user approval.

---

## 3: Component queries require repeated optional component lookups

+++
status: open
priority: medium
kind: enhancement
labels: effort:m
created: 2026-09-23T17:28:58Z
updated: 2026-09-23T18:01:44Z
+++

World.query(with:) filters entities by component presence but returns untyped Entity handles. Systems must then retrieve each requested component through an optional subscript and repeat presence checks. Starfall MovementSystem and CollisionSystem demonstrate this repeated query-and-guard pattern. The query result cannot express typed access to the components it matched.

- `2026-09-23T18:01:44Z`: Related to #6: typed query ergonomics and fast access overlap, but #3 concerns compile-time component access while #6 concerns lookup cost. #7 investigates parameter-pack feasibility for both.

---

## 4: Multiple simulation substeps produce separate storage invalidations within one rendered frame

+++
status: open
priority: medium
kind: enhancement
labels: effort:m
created: 2026-09-23T17:47:35Z
updated: 2026-09-23T18:01:44Z
+++

Storage observation is batched per outermost world.update(), not per rendered frame. Apps that perform several sequential simulation substeps per frame receive one storage invalidation for each changed substep. Starfall uses this pattern. Notification volume therefore scales with substep count even when the UI only needs the final frame state. The existing per-update guarantee remains correct; batching across sequential updates is not currently supported.

- `2026-09-23T18:01:44Z`: Related to #5: notification counts across substeps are part of the observation measurements. This issue concerns batching semantics across sequential updates.

---

## 5: Observation overhead and world-wide redraw scope lack dedicated measurements

+++
status: open
priority: medium
kind: task
labels: effort:m
created: 2026-09-23T17:47:35Z
updated: 2026-09-23T18:01:44Z
+++

World storage observation now tracks ECS reads and invalidates at world scope. Correctness tests cover notification batching, but dedicated measurements do not establish its runtime overhead or the UI work caused by broad invalidation. Measure representative large-world workloads with and without active observers, ordinary and fast-query reads/writes, sequential simulation substeps, and multiple views reading unrelated entities or components. Distinguish storage notifications from actual SwiftUI body evaluations and rendering work. These measurements are needed before deciding whether finer-grained observation is worthwhile.

- `2026-09-23T18:01:44Z`: Related to #4 (substep notification volume) and #6 (component-access cost). Measurements must distinguish observation overhead from dictionary lookup/cast cost.

---

## 6: Fast component access still performs per-access dictionary lookups and casts

+++
status: open
priority: medium
kind: enhancement
labels: effort:l
created: 2026-09-23T17:57:52Z
updated: 2026-09-23T18:01:44Z
+++

EntityRef stores type-erased columns in a ComponentType-keyed dictionary. Every component read/write performs a lookup and cast, including repeated accesses in tight simulation loops. PLAN.md identified this as a performance concern, but its timings are historical and not verified against the current implementation. Establish current Release baselines and assess typed fast-query access without losing storage observation or component events. Related: #3 covers typed query ergonomics; #5 covers observation overhead.

- `2026-09-23T18:01:44Z`: Related to #3 (typed access), #5 (observation measurements), and #7 (parameter-pack feasibility). Performance changes must preserve existing observation and component-event behavior.

---

## 7: Parameter-pack typed query references remain unverified on current Swift

+++
status: open
priority: low
kind: task
labels: effort:s
created: 2026-09-23T17:57:52Z
updated: 2026-09-23T18:01:44Z
+++

The retired PLAN.md records a compiler crash when attempting EntityRef<each T: Component>: signal 11 in emitPackExpansionIntoPack. There is no current reproduction or verification against the supported toolchain. Determine whether the limitation still applies and capture a minimal reproduction and compiler version if it does. Explicit overloads and macros were alternatives in the old plan, not committed requirements.

- `2026-09-23T18:01:44Z`: Related to #3 and #6: this bounded compiler investigation informs typed-query designs, without committing to a specific implementation.

---

## 8: Empty archetypes remain allocated after component transitions

+++
status: open
priority: low
kind: enhancement
labels: effort:l
created: 2026-09-23T17:57:52Z
updated: 2026-09-23T18:01:44Z
+++

Adding and removing component types can leave empty intermediate archetypes in World. No empty-archetype reclamation exists. Long-lived worlds with changing component signatures can retain unused storage and query-cache entries. Any future reclamation must account for registered query caches and the lifetime rules of lazy sequences and query references.

---

## 9: System count changes are not observable for debug interfaces

+++
status: open
priority: low
kind: enhancement
labels: effort:s
created: 2026-09-23T17:57:52Z
updated: 2026-09-23T18:01:44Z
+++

World.systemCount reports the registered system count but reads ignored system storage without establishing an observation dependency. Debug views reading only systemCount do not automatically refresh when systems are added or removed. Storage observation does not cover system registration. This was a future consideration in PLAN.md, not part of the completed storage-observation contract.

---

## 10: Decide whether pause and resume belong in World

+++
status: open
priority: low
kind: task
labels: effort:s
created: 2026-09-23T17:57:52Z
updated: 2026-09-23T18:01:44Z
+++

Applications currently own pause state and decide whether to call World.update. There is no agreed reason to move this policy into the ECS. Decide whether pause belongs in World or remains application-owned. Record the rationale and, if library support is warranted, define simulationTime, system execution, and direct-write behavior while paused. This is a design task only; implementation requires a separate decision.

---

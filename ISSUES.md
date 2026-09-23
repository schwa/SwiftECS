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
status: closed
priority: medium
kind: enhancement
labels: effort:m
created: 2026-09-23T17:28:58Z
updated: 2026-09-23T18:14:15Z
closed: 2026-09-23T18:14:15Z
+++

World.query(with:) filters entities by component presence but returns untyped Entity handles. Systems must then retrieve each requested component through an optional subscript and repeat presence checks. Starfall MovementSystem and CollisionSystem demonstrate this repeated query-and-guard pattern. The query result cannot express typed access to the components it matched.

- `2026-09-23T18:01:44Z`: Related to #6: typed query ergonomics and fast access overlap, but #3 concerns compile-time component access while #6 concerns lookup cost. #7 investigates parameter-pack feasibility for both.
- `2026-09-23T18:07:14Z`: Investigation #7 found typed column packs viable on Swift 6.4, with helper-based reads and a variadic setter to avoid two compiler errors. See Experiments/TypedQueryPacks/README.md and the test-only prototype. Tuple access is proven; compile-time membership for component-type subscripts is not.
- `2026-09-23T18:14:15Z`: Added World.typedQuery with typed tuple reads and variadic row.set writes, plus optional predicate filtering and registered-query support. No optional component lookups are needed on this path. Existing APIs remain available. Starfall movement now uses the public API. Debug/Release tests cover component packs, filtering, observation, and component events.

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
- `2026-09-23T19:29:01Z`: Tracked by umbrella #14 alongside observation measurements in #5 and row-cost work in #13.

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
- `2026-09-23T18:22:31Z`: Initial query comparison: one rearming storage observer adds no clear large cost in the measured single-archetype workload. This does not isolate the cost of observation instrumentation and does not measure SwiftUI body evaluation/rendering, multiple unrelated views, or substeps. See Experiments/TypedQueryPacks/Performance.md. Broader investigation remains open.
- `2026-09-23T18:42:11Z`: Related investigation #13 measures row read/write costs without active subscribers. Broader instrumentation cost and SwiftUI behavior remain unmeasured here.
- `2026-09-23T19:29:01Z`: Tracked by umbrella #14. Current baseline and trace provenance are in Experiments/TypedQueryPacks/Performance.md and ~/Desktop/ECS-Profiles/README.md.

---

## 6: Fast component access still performs per-access dictionary lookups and casts

+++
status: closed
priority: medium
kind: enhancement
labels: effort:l
created: 2026-09-23T17:57:52Z
updated: 2026-09-23T18:22:31Z
closed: 2026-09-23T18:22:31Z
+++

EntityRef stores type-erased columns in a ComponentType-keyed dictionary. Every component read/write performs a lookup and cast, including repeated accesses in tight simulation loops. PLAN.md identified this as a performance concern, but its timings are historical and not verified against the current implementation. Establish current Release baselines and assess typed fast-query access without losing storage observation or component events. Related: #3 covers typed query ergonomics; #5 covers observation overhead.

- `2026-09-23T18:01:44Z`: Related to #3 (typed access), #5 (observation measurements), and #7 (parameter-pack feasibility). Performance changes must preserve existing observation and component-event behavior.
- `2026-09-23T18:07:14Z`: Investigation #7 demonstrates retained typed columns without per-access dictionary lookup in Debug and Release. See Experiments/TypedQueryPacks/README.md. No performance measurement or production iterator implementation yet.
- `2026-09-23T18:14:15Z`: The new public typedQuery API binds typed columns once per matching archetype and avoids per-component dictionary lookups on rows. Functional tests pass in Debug and Release. Keep this issue open for comparative Release performance measurements and assessment of remaining costs.
- `2026-09-23T18:22:31Z`: Typed queries now bind columns once per archetype and avoid per-access dictionary lookups/casts. Matched Release comparison on M5 Max, 100K entities: median 111.405 ms/update typed, 198.465 ms fast references, 309.467 ms entity handles. Three serial samples, warm-up, equivalent reads/writes, registered queries, setup excluded. Correctness and observation tests pass. Results and reproducible opt-in benchmark: Experiments/TypedQueryPacks/Performance.md. This resolves the lookup-path comparison, not all ECS performance concerns; broader observation measurements remain #5.

---

## 7: Parameter-pack typed query references remain unverified on current Swift

+++
status: closed
priority: low
kind: task
labels: effort:s
created: 2026-09-23T17:57:52Z
updated: 2026-09-23T18:07:14Z
closed: 2026-09-23T18:07:14Z
+++

The retired PLAN.md records a compiler crash when attempting EntityRef<each T: Component>: signal 11 in emitPackExpansionIntoPack. There is no current reproduction or verification against the supported toolchain. Determine whether the limitation still applies and capture a minimal reproduction and compiler version if it does. Explicit overloads and macros were alternatives in the old plan, not committed requirements.

- `2026-09-23T18:01:44Z`: Related to #3 and #6: this bounded compiler investigation informs typed-query designs, without committing to a specific implementation.
- `2026-09-23T18:07:14Z`: Investigation complete on Apple Swift 6.4 (swiftlang-6.4.0.34.1). Typed ECS column packs pass Debug and Release tests. Direct array access in pack expansion and single-element tuple-property assignment fail with reproducible diagnostics; generic read helpers and variadic setter methods work. Retained standalone repro variants and ECS-backed tests. Historical signal-11 crash not reproduced; Swift 6.2 remains unverified. Findings: Experiments/TypedQueryPacks/README.md. No production API changes.

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

## 11: Component-event dispatch constructs debug type names even without observers

+++
status: closed
priority: high
kind: enhancement
labels: effort:s
created: 2026-09-23T18:33:29Z
updated: 2026-09-23T18:38:35Z
closed: 2026-09-23T18:38:35Z
+++

Release Time Profiler samples show substantial overhead in component-event dispatch during typed-query writes. ObserverRegistry.notifyChanged constructs ComponentType(T.self), including String(describing: type), before checking whether handlers exist. The benchmark registers no component-event handlers, yet every write pays this cost.

In samples containing QueryBenchmarkSystem.update and TypedEntityRef or TypedQueryIterator, 52.2% of selected CPU weight includes ObserverRegistry.notifyChanged and 48.8% includes String.init(describing:). These inclusive weights overlap. The run uses 100,000 entities and takes approximately 112 ms per typed-query update. Stacks include reflection, dynamic casts, and protocol-conformance checks beneath name construction.

Expected: absence of component-event subscribers should not incur debug-name construction for each write. Event delivery with subscribers and batched Swift Observation must remain correct.

Reproduce with the opt-in Release comparison in Tests/ECSTests/QueryPerformanceTests.swift. Measurements and profiling methodology: Experiments/TypedQueryPacks/Performance.md. Local trace: /tmp/ecs-query-profile.trace. Related: #5 covers broader observation overhead. This report concerns component-event dispatch, not SwiftUI notification counts.

- `2026-09-23T18:38:35Z`: ObserverRegistry now dispatches by ObjectIdentifier, skips empty registries, and removes empty handler buckets. No debug type names are constructed for registration or event dispatch. Added regression tests for removal/re-registration, self-removal, and distinct type identity. Core and demo tests, macOS build, and strict lint pass. Release typed-query median fell from 111.405 to 54.070 ms/update. Follow-up profile shows observer dispatch below 1% of selected typed-query samples. Details in Experiments/TypedQueryPacks/Performance.md.

---

## 12: Typed iterator advancement spends about 32 ms per 100K rows before component work

+++
status: closed
priority: high
kind: enhancement
labels: effort:m
created: 2026-09-23T18:42:11Z
updated: 2026-09-23T18:47:11Z
closed: 2026-09-23T18:47:11Z
+++

After #11, the typed-query benchmark still takes about 54 ms/update. Release Time Profiler attributes 59.9% of selected typed-query CPU samples to TypedQueryIterator.next, including per-row generic metadata instantiation, TypedEntityRef construction, and value-witness copy/destruction work. Inclusive percentages overlap.

A separate cost-isolation test measures 100K rows: iterator advancement plus an entity-ID checksum takes 31.715 ms; fresh component reads take 38.321 ms; the same reads from pre-collected rows take 6.102 ms. Query construction is only about 1.9 microseconds per call in this single-archetype workload. Three serial samples, rotated order, warm-up, setup excluded, correctness checks outside timing.

The public typed iterator incurs substantial overhead before useful component work. Preserve sequence behavior, component order, observation coverage, and existing lifetime constraints when addressing it. Pre-collected rows are an isolation experiment, not a safe workaround across structural changes.

Evidence: Tests/ECSTests/TypedQueryCostTests.swift and Experiments/TypedQueryPacks/Performance.md. Local trace: /tmp/ecs-issue-11-profile.trace. Historical lookup optimization #6 is complete; this concerns the newly measured typed-iterator cost.

- `2026-09-23T18:42:11Z`: Related to #13, which isolates remaining component reads/writes after excluding typed iteration. These are separate costs; improvements to one do not establish the cost of the other.
- `2026-09-23T18:47:11Z`: TypedQueryStorage is now shared reference storage. Each row retains that storage plus its index instead of expanding/copying column packs during next(). Public API unchanged. Iterator-only median fell from 31.715 to 2.868 ms/100K rows; full isolation workload from 56.309 to 24.726 ms. Follow-up profile reduces iterator share from 59.9% to 9.7% inclusive. Retained read/write costs remain similar. Core/demo tests, macOS build, and strict lint pass. Added iterator-copy/index regression coverage. Measurements recorded in Experiments/TypedQueryPacks/Performance.md.

---

## 13: Typed component reads and writes remain costly after iterator overhead is excluded

+++
status: new
priority: high
kind: enhancement
labels: effort:m
created: 2026-09-23T18:42:11Z
+++

A Release isolation benchmark pre-collects typed rows before timing, avoiding TypedQueryIterator.next and row construction during updates. On 100K entities, reads take a median 6.102 ms/update; equivalent reads plus position arithmetic and writes of Transform and Physics take 22.013 ms/update. No component-event or Swift Observation subscribers are registered. Updates retain normal storage batching.

The retained-row read/write workload alone exceeds 16.7 ms, even before rendering or fresh iteration. Existing profile samples include generic metadata lookup beneath Array.subscript.modify, tuple handling, and row setters. These results do not establish whole-array copy-on-write copies or prove that replacing Array with spans will help.

Identify the remaining read/write costs while preserving component-event delivery, storage invalidation, and correctness. The retained-row workload is only an isolation experiment without structural changes.

Evidence: Tests/ECSTests/TypedQueryCostTests.swift and Experiments/TypedQueryPacks/Performance.md. Related: #12 isolates iterator advancement; #5 covers broader observation measurements. Measurements use three rotated Release samples, warm-up, and setup/result checks outside the timer.

- `2026-09-23T18:47:11Z`: After #12 removes most iterator overhead, fresh read/write median is 24.726 ms and retained read/write is 21.891 ms. New profile: TypedEntityRef.set is 67.3% inclusive, Array.subscript.modify 44.9%, generic metadata lookup 53.7% (overlapping). Trace /tmp/ecs-issue-12-profile.trace. This further isolates the remaining setter/read costs; no evidence yet of whole-array copying.
- `2026-09-23T18:50:41Z`: Tested extracting the array write into a generic helper. Fresh read/write median: baseline 24.726 ms, helper 24.619 ms, @inline(never) helper 25.447 ms. Retained writes: 21.891, 21.658, 22.439 ms respectively. Three Release samples per variant. No meaningful gain from normal helper; noinline is slower. Removed both variants, leaving production code unchanged. Results recorded in Experiments/TypedQueryPacks/Performance.md.
- `2026-09-23T19:29:01Z`: Tracked by umbrella #14. Latest profile is preserved at ~/Desktop/ECS-Profiles/typed-query-0ab9af6b.trace with benchmark logs, analysis script/summary, and provenance notes. The trace matches current production code; subsequent helper experiments were reverted.
- `2026-09-23T19:39:22Z`: Further investigation: Column setter 24.175 ms, scoped buffer write 22.681 ms, ContiguousArray 22.742 ms; these variants were removed. Retained candidate: @inlinable typed accessors with required @usableFromInline internals, original Array storage. Isolation read/write median 15.069 ms; retained-row writes 11.626 ms. Longer typed-only profile: 14.987 ms unobserved, 15.003 ms observed. Mixed comparison varied up to 16.7 ms. Metadata remains 40.7% inclusive under the typed-only update filter. Debug/Release tests, demo tests/build, and lint pass. Keep open: improvement leaves little frame headroom and residual metadata costs. See Performance.md and ~/Desktop/ECS-Profiles/typed-query-inline-experiment.trace.

---

## 14: Track ECS performance against the 60 Hz simulation budget

+++
status: open
priority: high
kind: task
labels: effort:l
created: 2026-09-23T19:28:16Z
updated: 2026-09-23T19:29:01Z
+++

Umbrella issue for the remaining ECS performance work. The current 100K-entity Release workload takes approximately 25 ms per update, exceeding the 16.7 ms budget for 60 Hz before rendering. This is a synthetic simulation workload, not a measured Starfall frame time.

Current evidence: Experiments/TypedQueryPacks/Performance.md. The latest Time Profiler capture matches production code at 0ab9af6b; later write-helper experiments were reverted. Durable local trace: ~/Desktop/ECS-Profiles/typed-query-0ab9af6b.trace, with benchmark output, stack summary, and provenance notes alongside it. The capture includes all processes and must be reviewed before sharing.

Remaining work:
- #13: typed component reads/writes. Current profile is dominated by setter work, array modification, and generic metadata. The plain and non-inlined write-helper experiments did not help.
- #5: broader observation overhead and actual SwiftUI work, including multiple observing views.
- #4: sequential simulation substeps each produce storage invalidation.

Completed milestones: #6 introduced and measured typed access; #11 removed debug-name construction from observer dispatch; #12 removed most per-row iterator construction overhead. Comparable workload medians progressed from about 111 ms to 54 ms to 25 ms.

Completion criteria: repeatable Release measurements below 16.7 ms for the defined 100K-entity workload, with rendering headroom reported rather than implied; characterization of observation and component-event costs; correctness tests still passing; retained profiles and measurement notes identifying the tested revision, toolchain, hardware, workload, and limitations. Timing improvements must not silently omit event delivery or observation. This issue coordinates the related work rather than duplicating its implementation scope.

- `2026-09-23T19:39:22Z`: Current candidate uses cross-module specialization of typed accessors. Typed-only 100-frame samples now measure about 15 ms/update; mixed comparison reaches 16.5–16.7 ms, so no claim of reliable rendering headroom. Latest preserved trace: ~/Desktop/ECS-Profiles/typed-query-inline-experiment.trace, with benchmark log, summary, provenance, and patch. Older 0ab9af6b trace remains as the previous baseline. #13 and #5 remain open.

---

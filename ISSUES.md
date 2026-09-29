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
status: closed
priority: medium
kind: enhancement
labels: effort:m, area:observation
created: 2026-09-23T17:47:35Z
updated: 2026-09-29T14:55:31Z
closed: 2026-09-29T14:55:31Z
+++

Storage observation is batched per outermost world.update(), not per rendered frame. Apps that perform several sequential simulation substeps per frame receive one storage invalidation for each changed substep. Starfall uses this pattern. Notification volume therefore scales with substep count even when the UI only needs the final frame state. The existing per-update guarantee remains correct; batching across sequential updates is not currently supported.

\- `2026-09-23T18:01:44Z`: Related to #5: notification counts across substeps are part of the observation measurements. This issue concerns batching semantics across sequential updates.
\- `2026-09-23T19:29:01Z`: Tracked by umbrella #14 alongside observation measurements in #5 and row-cost work in #13.
\- `2026-09-29T14:38:22Z`: Related to #15: an isolated render-snapshot bridge also needs a frame publication boundary. This issue remains about batching sequential simulation substeps, not simulation ownership or snapshot transport.
\- `2026-09-29T14:55:31Z`: Added an opt-in World.batchingObservation { } scope that coalesces storage-observation notifications across sequential update(deltaTime:) substeps. It publishes a single storage invalidation when the outermost scope exits, so a per-frame loop with N substeps notifies SwiftUI once instead of N times.

This reuses the existing MutationCoordinator batch depth, so no default semantics change: unbatched updates still publish once each, component-event observers still fire synchronously, and a thrown substep still flushes the pending invalidation as the scope unwinds. It is a serial API and does not bracket the async parallel update overloads (documented).

Regression tests (ObservationBatchTests): 4 sequential updates produce 4 notifications unbatched and exactly 1 when wrapped; a mid-frame throw still publishes once; nesting and body-result return are covered. Full Debug suite (265) green; lint clean.

No frame-boundary guessing was required: the application opts in by wrapping its substep loop. simulationTime remains a separate observable and is out of scope here; broader observation/rendering measurement stays in #5.

---

## 5: Observation overhead and world-wide redraw scope lack dedicated measurements

+++
status: closed
priority: medium
kind: task
labels: effort:m, area:observation, area:performance
created: 2026-09-23T17:47:35Z
updated: 2026-09-29T14:59:00Z
closed: 2026-09-29T14:59:00Z
+++

World storage observation now tracks ECS reads and invalidates at world scope. Correctness tests cover notification batching, but dedicated measurements do not establish its runtime overhead or the UI work caused by broad invalidation. Measure representative large-world workloads with and without active observers, ordinary and fast-query reads/writes, sequential simulation substeps, and multiple views reading unrelated entities or components. Distinguish storage notifications from actual SwiftUI body evaluations and rendering work. These measurements are needed before deciding whether finer-grained observation is worthwhile.

\- `2026-09-23T18:01:44Z`: Related to #4 (substep notification volume) and #6 (component-access cost). Measurements must distinguish observation overhead from dictionary lookup/cast cost.
\- `2026-09-23T18:22:31Z`: Initial query comparison: one rearming storage observer adds no clear large cost in the measured single-archetype workload. This does not isolate the cost of observation instrumentation and does not measure SwiftUI body evaluation/rendering, multiple unrelated views, or substeps. See Experiments/TypedQueryPacks/Performance.md. Broader investigation remains open.
\- `2026-09-23T18:42:11Z`: Related investigation #13 measures row read/write costs without active subscribers. Broader instrumentation cost and SwiftUI behavior remain unmeasured here.
\- `2026-09-23T19:29:01Z`: Tracked by umbrella #14. Current baseline and trace provenance are in Experiments/TypedQueryPacks/Performance.md and ~/Desktop/ECS-Profiles/README.md.
\- `2026-09-29T04:24:01Z`: Preserved from retired performance notes: the historical single-archetype comparison used 100K entities, registered queries, fresh worlds, warm-up, and three rotated Release samples. One synchronous rearming storage observer added no clear large cost, but both variants retained observation instrumentation. No SwiftUI rendering or unrelated-view measurement was performed. QueryPerformanceTests and TypedQueryCostTests remain available via ECS_RUN_BENCHMARKS=1. Historical captures/logs were recorded under ~/Desktop/ECS-Profiles, including typed-query-column-inline.trace; their current presence is unverified, and all-process captures need review before sharing. Old document references in earlier comments are historical; broader work here remains open.
\- `2026-09-29T14:38:22Z`: Related to #15: snapshot publication can change UI invalidation scope and cadence. Observation/rendering measurements here can inform that design without assuming snapshots are already implemented.
\- `2026-09-29T14:59:00Z`: Added opt-in ObservationOverheadBenchmarkTests (ECS_RUN_OBSERVATION_BENCHMARKS=1) isolating storage-observation cost and notification volume from work, across access styles, observer counts, and substep batching. Overridable via ECS_OBS_ENTITIES/ROUNDS/FRAMES. SwiftUI body/rendering measurement is explicitly out of scope (noted in code).

Measured Apple M5 Max (18 processors), macOS 27.0 (26A428), Swift 6.4, Release; 100,000 entities, rounds=3, frames=30, one storage publish per frame:

Work vs observer count (median ms/frame, notifications/frame):
- entityHandles: 0 obs 174.89 (0/f); 1 obs 175.75 (1/f); 8 obs 175.59 (8/f).
- typedQuery: 0 obs 9.56 (0/f); 1 obs 9.74 (1/f); 8 obs 11.92 (8/f).

Notification volume across 4 sequential substeps: unbatched 4 notifications; wrapped in World.batchingObservation (see #4) 1 notification.

Findings:
- Storage observation publishes exactly once per frame regardless of observer count; each armed observer is notified once and rearms.
- Per-observer overhead is negligible against heavy entity-handle work (~0.5%) but measurable on the fast typed path: 0->1 observer +~2%, 1->8 observers +~22% (9.74->11.92 ms). The cost is each observer recomputing its read on every world-wide invalidation; two of the eight observers scan 100k entities per rearm, so this reflects world-wide redraw scope, not per-write dispatch.
- Substep notifications scale with substep count unless batched; batchingObservation coalesces them to one.

Distinguishing notifications from work: notification count is one publish/frame (or N per substeps unbatched), independent of the large access-style work gap between entity handles and typed queries. Whether finer-grained (per-component or per-query) observation is worthwhile depends on real SwiftUI body/rendering cost, which remains unmeasured here and is out of scope for this issue. README updated with the command and headline results.

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
- `2026-09-29T04:24:01Z`: Documentation cleanup: the standalone Probe.swift and TypedQueryPackTests remain. Working and negative probe commands, historical diagnostics, and the unverified Swift 6.2 minimum are now captured in #44. The removed investigation notes remain in version control.

---

## 8: Empty archetypes remain allocated after component transitions

+++
status: closed
priority: low
kind: enhancement
labels: effort:l, area:storage
created: 2026-09-23T17:57:52Z
updated: 2026-09-29T15:26:41Z
closed: 2026-09-29T15:26:41Z
+++

Adding and removing component types can leave empty intermediate archetypes in World. No empty-archetype reclamation exists. Long-lived worlds with changing component signatures can retain unused storage and query-cache entries. Any future reclamation must account for registered query caches and the lifetime rules of lazy sequences and query references.

\- `2026-09-29T15:26:41Z`: Implemented empty-archetype reclamation after component add/remove transitions and entity destruction.

Change: World.reclaimIfEmpty(archetype) drops an archetype once its last entity leaves. It is called at the end of both moveEntity variants (add and remove component) on the vacated source archetype, and in removeEntity after the entity's archetype loses its last row. Guards:
- The base empty-signature archetype is never reclaimed (it is the reusable home for component-less entities and is recreated constantly otherwise).
- Only archetypes with no remaining entities are removed.
- Removal bumps the query generation (queries.invalidateArchetypes()), so registered query caches rebuild without the reclaimed archetype on their next prepare.

Safety against lifetime rules: reclamation is result-invariant because an empty archetype matches no entities, so query results are unchanged. Archetype is a class held strongly by lazy QuerySequence/QueryIterator, typed SystemQueryStorage, and snapshots; removing it from World.archetypes cannot deallocate it mid-iteration. A sequence captured before reclamation keeps its own reference and safely iterates (now empty). If an entity later transitions back into a reclaimed signature, getOrCreateArchetype recreates a fresh archetype and invalidates caches. Reclamation only runs inside structural mutations, which cannot occur during the parallel worker phase.

Regression tests (ArchetypeReclamationTests), red before the fix and green after (verified by temporarily removing the three reclaim calls: the reclamation assertions failed): reclamation on component add and on remove (target archetype absent, count unchanged, results intact); base empty archetype retained and reused; destroy reclaims the archetype; archetypes still holding entities are not reclaimed; registered queries stay correct across reclaim/re-home/removal; and a captured lazy sequence survives reclamation of its archetype (iterates empty, a fresh sequence sees the re-homed entity).

Verification: full suite 287 green; lint clean; the 100k system-update stress test is unaffected (~15.2 ms/frame), since the empty-check guard is negligible for non-transitioning workloads. Any future reclamation-cache work remains compatible; this change touches only per-transition cleanup.

---

## 9: System count changes are not observable for debug interfaces

+++
status: closed
priority: low
kind: enhancement
labels: effort:s
created: 2026-09-23T17:57:52Z
updated: 2026-09-29T04:24:01Z
closed: 2026-09-29T04:24:01Z
+++

World.systemCount reports the registered system count but reads ignored system storage without establishing an observation dependency. Debug views reading only systemCount do not automatically refresh when systems are added or removed. Storage observation does not cover system registration. This was a future consideration in PLAN.md, not part of the completed storage-observation contract.

- `2026-09-23T19:55:27Z`: Related idea #17 evaluates ECS-backed scheduling and its observation contract; system-count observation remains a separate current-API concern.
- `2026-09-29T04:24:01Z`: Documentation audit found this already resolved by ECS-backed scheduling (#17). World.systemCount reads snapshot(with: SystemDescriptor.self), which establishes storage observation. PipelineTests includes scheduling changes notify storage and system counts, covering registration and removal invalidation. Closed from current source and existing test coverage; no new code changes or test run were needed.

---

## 10: Decide whether pause and resume belong in World

+++
status: closed
priority: low
kind: task
labels: effort:s, area:systems
created: 2026-09-23T17:57:52Z
updated: 2026-09-29T15:27:37Z
closed: 2026-09-29T15:27:37Z
+++

Applications currently own pause state and decide whether to call World.update. There is no agreed reason to move this policy into the ECS. Decide whether pause belongs in World or remains application-owned. Record the rationale and, if library support is warranted, define simulationTime, system execution, and direct-write behavior while paused. This is a design task only; implementation requires a separate decision.

\- `2026-09-23T19:55:27Z`: Related idea #17 evaluates selectable pipelines. Consider that design when deciding whether pause is world-wide or application-owned.
\- `2026-09-29T15:27:37Z`: Decision: pause and resume remain application-owned. No library pause API is added.

Rationale:
- World has no run loop. update(deltaTime:) is caller-driven per frame/substep, so 'pause' is simply 'do not call update'. A world.paused flag would only gate update internally - pure indirection with no new capability.
- simulationTime advances only inside update(advancesTime: true). Not calling update already freezes simulation time, which is exactly the desired paused behavior; a library pause would have to re-specify this and could only match it.
- The pipeline model already provides selective pause, and more expressively than a global flag. run(_:deltaTime:) executes a chosen pipeline without advancing simulation time, so an application can keep services/UI/audio systems running while skipping the gameplay pipeline. A single world.paused switch would be strictly less capable.
- 'Which systems run while paused' is application policy (gameplay vs UI vs services). Encoding it in World would force a policy the library should not own; selectable pipelines let the app decide.
- Direct component and relationship writes must stay available while paused - pause menus, upgrades (Survival's needsUpgrade/choose), and restarts all mutate a paused world. A pause that blocked writes would break these; a pause that allowed them adds nothing over app-owned state.
- Applications already model pause as their own observable state that also drives UI (both demos hold a session-level 'paused' bool gating world.update). Duplicating it in World would create two sources of truth.

Evidence from the demos: StarfallSupport/GameSession and SurvivalSupport/SurvivalSession each own a 'paused' flag and simply skip world.update while paused; they still mutate the world for menus/upgrades/restart. This is the intended, sufficient pattern.

Conclusion favors the current state clearly, so this is a decision (not a punt) with no functional change. Added a short README note under the pipelines section documenting the pattern: pause by not calling update (freezes simulationTime), use run(_:deltaTime:) for selective systems while paused, and direct writes remain available. Related: #17 (selectable pipelines) supplies the selective-pause mechanism.

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
status: closed
priority: high
kind: enhancement
labels: effort:m
created: 2026-09-23T18:42:11Z
updated: 2026-09-23T21:17:09Z
closed: 2026-09-23T21:17:09Z
+++

A Release isolation benchmark pre-collects typed rows before timing, avoiding TypedQueryIterator.next and row construction during updates. On 100K entities, reads take a median 6.102 ms/update; equivalent reads plus position arithmetic and writes of Transform and Physics take 22.013 ms/update. No component-event or Swift Observation subscribers are registered. Updates retain normal storage batching.

The retained-row read/write workload alone exceeds 16.7 ms, even before rendering or fresh iteration. Existing profile samples include generic metadata lookup beneath Array.subscript.modify, tuple handling, and row setters. These results do not establish whole-array copy-on-write copies or prove that replacing Array with spans will help.

Identify the remaining read/write costs while preserving component-event delivery, storage invalidation, and correctness. The retained-row workload is only an isolation experiment without structural changes.

Evidence: Tests/ECSTests/TypedQueryCostTests.swift and Experiments/TypedQueryPacks/Performance.md. Related: #12 isolates iterator advancement; #5 covers broader observation measurements. Measurements use three rotated Release samples, warm-up, and setup/result checks outside the timer.

- `2026-09-23T18:47:11Z`: After #12 removes most iterator overhead, fresh read/write median is 24.726 ms and retained read/write is 21.891 ms. New profile: TypedEntityRef.set is 67.3% inclusive, Array.subscript.modify 44.9%, generic metadata lookup 53.7% (overlapping). Trace /tmp/ecs-issue-12-profile.trace. This further isolates the remaining setter/read costs; no evidence yet of whole-array copying.
- `2026-09-23T18:50:41Z`: Tested extracting the array write into a generic helper. Fresh read/write median: baseline 24.726 ms, helper 24.619 ms, @inline(never) helper 25.447 ms. Retained writes: 21.891, 21.658, 22.439 ms respectively. Three Release samples per variant. No meaningful gain from normal helper; noinline is slower. Removed both variants, leaving production code unchanged. Results recorded in Experiments/TypedQueryPacks/Performance.md.
- `2026-09-23T19:29:01Z`: Tracked by umbrella #14. Latest profile is preserved at ~/Desktop/ECS-Profiles/typed-query-0ab9af6b.trace with benchmark logs, analysis script/summary, and provenance notes. The trace matches current production code; subsequent helper experiments were reverted.
- `2026-09-23T19:39:22Z`: Further investigation: Column setter 24.175 ms, scoped buffer write 22.681 ms, ContiguousArray 22.742 ms; these variants were removed. Retained candidate: @inlinable typed accessors with required @usableFromInline internals, original Array storage. Isolation read/write median 15.069 ms; retained-row writes 11.626 ms. Longer typed-only profile: 14.987 ms unobserved, 15.003 ms observed. Mixed comparison varied up to 16.7 ms. Metadata remains 40.7% inclusive under the typed-only update filter. Debug/Release tests, demo tests/build, and lint pass. Keep open: improvement leaves little frame headroom and residual metadata costs. See Performance.md and ~/Desktop/ECS-Profiles/typed-query-inline-experiment.trace.
- `2026-09-23T19:44:50Z`: Iterator specialization experiment: @inlinable next() and row initializer reduce iterator-only median from 2.851 to 0.789 ms. Fresh isolation read/write falls from 15.069 to 12.537 ms; retained writes stay similar. Longer typed-only profile: 13.418 ms/update without observer, 13.496 ms with one. Iterator share now 4.0% inclusive; setter 73.3%, generic metadata 40.7% overlap. Candidate retained; Debug/Release and demo tests/build plus lint pass. Latest trace ~/Desktop/ECS-Profiles/typed-query-iterator-inline.trace with patch against beb20431. Remaining setter work stays open.
- `2026-09-23T19:50:50Z`: Retested Column.setValue as @inlinable after accessor/iterator specialization. This time it helps: isolation fresh write median 10.319 ms vs preceding 12.537 ms. Back-to-back longer runs: direct array baseline 13.668 ms, column setter 9.951 ms (100K entities, three 100-update samples). Observed candidate 9.971 ms. New profile generic metadata share 28.8% inclusive, down from 40.7%; row setter 72.5%, column setter 54.3% overlap. Retained candidate preserves events/observation; all tests, demo build, and lint pass. Latest trace ~/Desktop/ECS-Profiles/typed-query-column-inline.trace with logs and patch against 1ff4b5db.
- `2026-09-23T21:17:09Z`: Closing after the user accepted the current performance goal. Cross-module accessor/iterator specialization and the inlinable column setter reduced the defined 100K-entity workload to approximately 10 ms/update. Profiles and measurements are retained in Experiments/TypedQueryPacks/Performance.md. Further optimization is not required for the accepted goal; broader workloads remain under #14/#5.

---

## 14: Track ECS performance against the 60 Hz simulation budget

+++
status: closed
priority: high
kind: task
labels: effort:l
created: 2026-09-23T19:28:16Z
updated: 2026-09-24T01:04:03Z
closed: 2026-09-24T01:04:03Z
+++

Umbrella issue coordinating ECS performance work against a 16.7 ms budget for 60 updates per second. The defined workload is 100,000 entities in one archetype, each reading and writing two components per update. This is a synthetic simulation workload, not a measured app frame time.

Outcome: the accepted component-update goal is met. The latest Release typed-query workload measures approximately 10.2 ms per update (median, 100-update samples, with and without a storage observer). Progress: about 111 ms, then 54, 25, 15, 13.4, and 10 ms across successive changes.

Completed work: #6 typed access; #11 removed debug type-name construction from observer dispatch; #12 shared typed-query storage; and cross-module specialization of accessors, iteration, and an inlinable column setter. Correctness tests pass in Debug and Release; component-event delivery and batched observation are preserved.

Measurements, methodology, and provenance are in Experiments/TypedQueryPacks/Performance.md, with retained traces and a patch under ~/Desktop/ECS-Profiles/. Traces include unrelated processes and need review before sharing. Numbers are hardware- and toolchain-specific and do not include app rendering headroom.

Remaining focused work continues separately: #5 broader observation and SwiftUI cost, #4 substep invalidation batching, and #19 relationship-heavy workloads. Closing this umbrella now that the component-update target is met; those issues track the rest.

- `2026-09-23T19:39:22Z`: Current candidate uses cross-module specialization of typed accessors. Typed-only 100-frame samples now measure about 15 ms/update; mixed comparison reaches 16.5–16.7 ms, so no claim of reliable rendering headroom. Latest preserved trace: ~/Desktop/ECS-Profiles/typed-query-inline-experiment.trace, with benchmark log, summary, provenance, and patch. Older 0ab9af6b trace remains as the previous baseline. #13 and #5 remain open.
- `2026-09-23T19:44:50Z`: Latest candidate specializes iterator advancement across modules. Longer typed-only samples measure about 13.4–13.5 ms/update for 100K entities, leaving roughly 3 ms before 16.7 ms, not a rendering guarantee. Current profile: ~/Desktop/ECS-Profiles/typed-query-iterator-inline.trace. Notes and methodology updated in Performance.md.
- `2026-09-23T19:50:50Z`: Current candidate reaches about 10 ms/update for the defined typed-query workload after an inlinable column setter. Back-to-back baseline 13.668 ms vs candidate 9.951 ms. This leaves about 6.7 ms of the 16.7 ms budget, but is not an app rendering measurement. Latest preserved profile is typed-query-column-inline.trace under ~/Desktop/ECS-Profiles/. Broader observation/event workloads remain outstanding.
- `2026-09-23T21:17:09Z`: Relationship-heavy scalability is tracked in #19. The accepted component-update goal is met at approximately 10 ms per 100K entities; remaining broader observation work stays in #5 and substep batching in #4.
- `2026-09-24T01:04:03Z`: Component-update goal met: about 10.2 ms per update for the defined 100K-entity workload in Release, below the 16.7 ms budget. Correctness, component events, and batched observation preserved. Retained profiles, patch, and methodology under ~/Desktop/ECS-Profiles and Experiments/TypedQueryPacks/Performance.md. Remaining performance work continues in #5, #4, and #19; this is not a claim of app rendering headroom.

---

## 15: Explore off-main simulation with isolated render snapshots

+++
status: closed
priority: low
kind: task
labels: idea, effort:m, area:observation, area:concurrency
created: 2026-09-23T19:53:23Z
updated: 2026-09-29T15:30:36Z
closed: 2026-09-29T15:30:36Z
+++

Idea: separate simulation ownership from rendering so ECS updates can run off the main actor without concurrent access to mutable World storage. World is currently unsynchronized; components need not be Sendable, query references retain mutable storage, and observer callbacks execute synchronously.

## Proposed direction (agreed for exploration)
A simulation actor owns World and receives input as commands. After each tick, it produces an immutable Sendable render snapshot containing only the data required by the renderer. A main-actor model publishes the latest snapshot to SwiftUI. Actor isolation does not imply a dedicated thread.

Investigate snapshot extraction/transfer costs, update cadence, stale-frame handling, command ordering, and observer execution context before committing to an API. Define Sendable boundaries without transferring live entities or query references between actors.

Double-buffering whole worlds is an alternative, not a requirement. It must account for structural changes, reference-type components, query-reference lifetimes, and renderer ownership before reusing buffers. Two buffers alone do not establish safe reuse.

This is a design idea, not an implementation commitment. Preserve the existing single-owner World model unless the investigation establishes a reason to change it.

\- `2026-09-29T14:37:53Z`: Triage: scope is a design investigation, not approval to implement the snapshot bridge. effort:m covers the ownership/API decision and representative extraction/transfer measurements. Parallel ECS execution now exists, but live World access remains unavailable while workers run and demo UI ticks remain serial.
\- `2026-09-29T14:38:22Z`: Related to #4 and #5: render snapshots and off-main ownership must define frame publication cadence and quantify UI/observation cost. Those issues cover substep batching and broad invalidation, not the snapshot bridge.
\- `2026-09-29T15:30:36Z`: Evaluation and recommendation: keep the single-owner World model. Off-main simulation with isolated render snapshots is achievable at the application layer today with no library changes, so no snapshot-bridge API is added now.

Assessment against the current parallel/ownership model:
- The parallel execution work is orthogonal to this idea. It parallelizes within one owner's run using task-local snapshots and blocks live world access while workers run; it does not move World off-main or decouple simulation cadence from rendering. The snapshot bridge is a separate concern.
- World is not Sendable, but it is not @MainActor either, so it can be confined to a custom actor and ticked off the main actor. Entities, query rows, and Entity/query references are non-Sendable, so the compiler already prevents live storage from escaping across an actor boundary. That is the critical safety property the issue asked to establish, and it holds by construction.
- The clean shape is: an actor owns World, receives Sendable input commands, ticks, and returns an immutable Sendable render snapshot containing only value data the renderer needs; a main-actor model publishes the latest snapshot to SwiftUI. This required zero library changes.

Cost and boundary notes:
- Snapshot extraction is O(rendered entities) per tick - a value copy of render data (see #40 on copy costs). It is bounded by the rendered subset, which is typically small; large scenes should measure it, but it is app-tunable (extract only what the renderer draws).
- Sendable boundary: the snapshot must be plain values (no live entities/rows/queries). The type system enforces this - the existing World.invalid concurrency compile-check fixture already proves a World reference cannot be captured into a Sendable/cross-actor closure.
- Observer execution context: the actor-owned world's Swift Observation would fire on the actor's executor, not main. In this design the app does not observe the world across the boundary; it observes the published snapshot on main, so world-level @Observable is simply unused across actors. No conflict.
- Double-buffering whole worlds remains rejected (structural changes, reference-type components, query-reference lifetimes). Snapshot-of-render-data is the safer approach and is what the PoC uses.
- Cadence and stale-frame handling (publish latest, drop intermediate) are application policy, consistent with the #10 decision that World owns no run loop.

Recommendation: do not add a library SimulationActor or generic snapshot API. It would be speculative and would bake in cadence and snapshot-shape policy that belongs to applications (same reasoning as #10). Revisit only if a concrete app need plus measured extraction/transfer costs justify a shared convenience. Preserve the single-owner World model.

Artifact (clearly safe, test-only): added OffMainSimulationTests, a proof of concept with an actor (SimulationActor) that owns a World, applies Sendable SimCommands, ticks a movement system, and returns a Sendable RenderSnapshot consumed by a @MainActor test. It compiles and passes under strict Swift 6 concurrency, demonstrating the feasibility and the enforced boundary without committing to any public API. No production code changed. Related: #4 (substep batching), #5 (invalidation cost), #10 (application-owned run policy), #40 (snapshot copy costs).

---

## 16: Explore relationships and traversal in queries

+++
status: closed
priority: low
kind: feature
labels: effort:l
created: 2026-09-23T19:55:27Z
updated: 2026-09-23T20:50:18Z
closed: 2026-09-23T20:50:18Z
+++

RFC 0001 proposes entity relationships and relationship-aware queries, but the library currently supports only component-signature predicates. There is no agreed relationship model or traversal contract.

Determine the smallest useful scope, including whether ChildOf alone is sufficient. Define cardinality, cycle handling, target deletion, traversal order, and the effects of relationship changes on query caches and observation. Preserve native Swift component support, including non-BitwiseCopyable values.

This is a design investigation, not approval to implement a general graph framework. Source: RFCs/0001-borrowing-ideas-from-flecs.md, sections 2 and 4.

- `2026-09-23T19:55:27Z`: Related: #17 evaluates phases and pipelines built on the relationship model. Its design depends on the scope decided here.
- `2026-09-23T20:50:18Z`: User approved general relationship pairs rather than ChildOf-only scope. Default parent deletion must detach children; an explicit recursive deletion operation provides rm -rf behavior. Implemented policies and boundaries are recorded in Experiments/Relationships.md.
- `2026-09-23T20:50:18Z`: Implemented marker-typed relationships, multi-target defaults, independent exclusive/acyclic policies, ChildOf conveniences, cycle-safe breadth-first traversal, detaching deletion, recursive deletion, and outgoing-link cloning. Added relationship and descendant predicates across ordinary/registered/lazy/fast/typed query paths, with live entity filtering and conservative archetype matching under negation. Relationship reads/writes participate in batched storage observation. 163 core tests pass in Debug and Release, 14 demo tests and macOS build pass, strict lint passes. Component-only benchmark remains about 10.7 ms/100K entities. No payloads, inherited component lookup, or scheduler migration in this scope.
- `2026-09-23T21:17:09Z`: Follow-up #19 tracks performance of deep/broad hierarchies, graph queries, reparenting, and deletion. Midnight Survivors now exercises FiredBy ownership links and a relationship-query HUD count; demo regression tests cover shooter deletion and projectile expiry.

---

## 17: Evaluate ECS-backed phases and selectable system pipelines

+++
status: closed
priority: low
kind: task
labels: idea
created: 2026-09-23T19:55:27Z
updated: 2026-09-24T19:55:30Z
closed: 2026-09-24T19:55:30Z
+++

RFC 0001 proposes phases as entities, dependency relationships, and query-selected pipelines. Current scheduling uses SystemEntry dependencies and a Swift-side topological sort. It does not expose phase entities or independently selectable pipelines.

Compare the proposed model with extending the current scheduler. Define ordering guarantees, subset execution, runtime pipeline changes, cycle/missing-dependency errors, and observation behavior. A query-based representation does not eliminate ordering or invalidation work.

This design depends on the relationship scope explored in #16. Related: #9 concerns observable system counts; #10 concerns ownership of pause/resume policy. Do not replace the scheduler until the trade-offs and intended use cases are agreed. Source: RFCs/0001-borrowing-ideas-from-flecs.md, section 1.

- `2026-09-23T20:50:18Z`: Relationship foundation from #16 is implemented: generic relation markers support independently exclusive/acyclic policies, direct and descendant predicates, and traversal. General graph traversal is breadth-first first-discovery order, not topological scheduling; pipeline ordering still needs its own design.
- `2026-09-24T19:37:27Z`: Evaluation written to Experiments/PhasesAndPipelines.md. Key finding: relationship traversal is BFS first-discovery, not topological, so a query/phase model does NOT eliminate the topo-sort — it only relocates where DependsOn edges are stored. Recommendation: keep Kahn's sort as the ordering primitive; if selectable pipelines become a real need, add a subset predicate on top and optionally derive dependencies from a DependsOn relation feeding the same sort. Do not replace the scheduler. Blocked on #9/#10 policy decisions.
- `2026-09-24T19:55:30Z`: Implemented the agreed RFC model, superseding the earlier evaluation recommendation. Phases and systems are entities; DependsOn and InPhase relationships define ordering; Pipeline queries select systems. Runs validate a fresh topological schedule and retain an execution snapshot, with deferred cleanup and existing nested mutation batching. Added runtime selection, explicit subset errors, before/after sugar, observable metadata, and documented lifecycle/time semantics. Package and demo builds pass; 191 package tests and 15 demo-support tests pass; SwiftLint is clean. Changes remain uncommitted.

---

## 18: Explore singleton components backed by ordinary entity storage

+++
status: closed
priority: low
kind: task
labels: idea, effort:s, area:storage
created: 2026-09-23T19:55:27Z
updated: 2026-09-29T15:33:01Z
closed: 2026-09-29T15:33:01Z
+++

World-level singleton components remain an exploratory Flecs-inspired idea. There is no agreed API or lifecycle contract for accessing global state through ordinary entity/component storage.

The open questions are singleton identity and uniqueness, creation and removal, query visibility, entity enumeration, and component-event/Swift Observation behavior. It is also undecided whether singleton components share one entity or use separate identities, and whether a library API offers enough value over application-owned well-known entities.

This is an exploratory design task, not an implementation commitment. The idea is preserved here from the retired Flecs RFC. Inherited component lookup is separate work in #43.

- `2026-09-29T14:37:53Z`: Triage: effort:s applies to the bounded singleton design decision, not implementation of a singleton API.
- `2026-09-29T14:38:22Z`: Related to #43: singleton state and inherited lookup both need explicit lookup, query, observation, and access contracts. They remain separate design investigations rather than one implicit global-state mechanism.
- `2026-09-29T15:33:01Z`: Evaluation and recommendation: singletons stay application-owned. No library singleton API is added, because no minimal, clearly-good, low-risk API emerges - the entity-backed approach carries an unresolved query-visibility hazard.

Assessment of the open questions:
- Identity and uniqueness: an entity-backed singleton is either one shared entity accumulating many component types (pollutes many queries) or one entity per singleton type (many hidden entities). Neither is obviously right, and uniqueness would need enforcement the storage layer does not provide today.
- Query visibility and enumeration: this is the deciding factor. Backed by ordinary storage, a singleton component is indistinguishable from any other entity - it appears in query and snapshot results and in entity counts. System entities already appear in normal queries, but they hold a distinct type (SystemDescriptor); a singleton of a gameplay type (for example a config or a Position) would pollute gameplay queries and counts and surprise users. Hiding singletons would require special-casing every query path, which contradicts the backed-by-ordinary-storage premise.
- Creation and removal, observation: these are the one clean part - set and remove fire the same storage notifications as any component, so lifecycle and Swift Observation behave consistently with no special work.
- Library API vs application-owned well-known entity: the only value a library API adds over an app-owned well-known entity is type-keyed access without stashing an id, plus uniqueness. That is marginal against the query-visibility hazard, the shared-vs-per-type decision, and a new lifecycle contract. A dedicated API would either inherit the query-visibility surprise or require a separate non-entity resource store, which is a different and larger design (out of scope for effort:s and not requested).

Recommendation: keep singletons application-owned. Model global state as one well-known entity whose id the app retains, read with world[id]?.get(_:). Uniqueness is the app holding a single id. This is zero-hazard and uses only existing API. Revisit only if a concrete need plus a decision on query visibility (a real resource store separate from entity storage) justifies it. Consistent with #10 (World owns no run-loop policy) and #15 (no speculative bridge API); inherited lookup remains separate in #43.

Artifacts (test-only, no production change): added SingletonPatternTests demonstrating the well-known-entity pattern (type-keyed read via retained id, mutation, destruction) and pinning the tradeoff (an entity-backed singleton is visible to ordinary queries and counts). Added a README note under the systems/queries section documenting that singletons are application-owned and why there is no library API.

---

## 19: Relationship-heavy workloads lack performance measurements

+++
status: closed
priority: medium
kind: task
labels: effort:m, area:performance, area:relationships, area:queries
created: 2026-09-23T21:17:09Z
updated: 2026-09-29T15:02:18Z
closed: 2026-09-29T15:02:18Z
+++

The relationship implementation has correctness coverage but no dedicated scale measurements. Descendant predicates traverse links separately for each candidate entity. Acyclic relationship insertion searches the graph before each new link, so deep hierarchy construction can become expensive.

Measure deep trees, broad trees, multi-parent graphs, frequent reparenting, direct and transitive queries, and recursive deletion. Include registered and unregistered queries, live membership changes, and observation. Use opt-in serial Release benchmarks with setup separated from the measured operation where appropriate, and verify results outside timing.

Record scaling and profiles before deciding whether transitive caching or other changes are warranted. Preserve cycle rejection, cache correctness, traversal order, and deletion semantics. Related: #16 introduced relationships; #14 tracks overall performance. Existing component-only benchmarks do not establish relationship performance.

\- `2026-09-29T14:38:22Z`: Related to #26 and #42: graph performance measurements can protect a relationship-ownership refactor and distinguish underlying traversal costs from schedule construction. Neither issue duplicates these relationship workload measurements.
\- `2026-09-29T15:02:18Z`: Added opt-in RelationshipBenchmarkTests (ECS_RUN_RELATIONSHIP_BENCHMARKS=1). Entity creation is outside the timer; all result counts are verified outside timing. Overridable via ECS_REL_ROUNDS/DEEP/BROAD/QUERY_REPEATS.

Measured Apple M5 Max (18 processors), macOS 27.0 (26A428), Swift 6.4, Release; rounds=3 medians:

Construction (linking only, entities pre-created):
- deep-chain depth=3000: 271.4 ms. Quadratic: the acyclic cycle check walks toward the root before each insert, so deep hierarchies are the costly case the issue flagged.
- broad-star width=50000: 17.5 ms. Linear, cheap acyclic checks.
- layered-dag layers=6 width=2000 fanIn=3 (30000 non-acyclic edges): 5.8 ms. No cycle search for non-acyclic links.

Mutation:
- reparent count=20000 iterations=5 (100000 exclusive setParent ops): 150.6 ms (~1.5 us/op), including outgoing-link replacement and reverse-index churn.

Queries (per operation):
- direct-query related(ChildOf, to: root) width=50000: unregistered 2.543 ms/query, registered 2.550 ms/query. Identical, confirming registration caches archetypes, not relationship matches.
- descendant-query descendant(of: root) over 111111 nodes: 48.4 ms/query. Expensive: the predicate evaluates per candidate entity.
- descendant-traversal root.descendants() (BFS) over 111111 nodes: 8.5 ms/traversal, far cheaper than the per-candidate predicate query.

Deletion:
- recursive-deletion of 111111 nodes: 104.2 ms.

Findings: the two clear caching candidates are deep acyclic construction (quadratic cycle checks) and descendant-predicate queries (per-candidate traversal). A single BFS traversal is already ~6x cheaper than the equivalent descendant snapshot, so a transitive index or a traversal-based descendant evaluator are the natural next investigations; none is implemented here. Cycle rejection, traversal order (BFS, root-excluded), reparenting, and recursive-deletion semantics are unchanged and asserted in the benchmark. No production code changed. README updated with the command and headline results. Related: #26 (relationship ownership), #42 (schedule-graph costs).

---

## 20: Lifecycle results conflate stale handles with foreign-world mistakes

+++
status: closed
priority: medium
kind: enhancement
created: 2026-09-23T22:35:47Z
updated: 2026-09-23T23:01:41Z
closed: 2026-09-23T23:01:41Z
+++

World.clone returns nil, World.destroy returns false, and recursive deletion returns zero for both stale handles and handles belonging to another world. Callers cannot distinguish an already-removed entity from an ownership mistake using the result. Define a consistent failure contract that distinguishes these cases without mutating either world. Current ownership checks are correct; the missing distinction is in the public API.

- `2026-09-23T23:01:41Z`: World lifecycle APIs now throw WorldError.foreignEntity for handles from another world. Stale handles preserve nil/false/0 results. Ownership is checked before existence; failed calls do not mutate or invalidate either world. Updated demos/examples and ownership regression tests.

---

## 21: System registration overloads have inconsistent failure behavior

+++
status: closed
priority: medium
kind: enhancement
created: 2026-09-23T22:35:47Z
updated: 2026-09-23T23:01:41Z
closed: 2026-09-23T23:01:41Z
+++

World.addSystem(system) is nonthrowing and traps when registration fails, while the overload with an explicit ID or dependencies throws SystemError. Adding an argument changes how callers must handle the same duplicate-system failure. The API does not provide a consistent registration failure contract across these forms.

- `2026-09-23T23:01:41Z`: Removed the trapping nonthrowing addSystem overload. The single registration API now throws with default or explicit IDs. Added duplicate-default-ID tests proving the rejected system is not initialized and registry contents remain unchanged. Updated all call sites.

---

## 22: Typed row writes cannot update only selected components

+++
status: closed
priority: medium
kind: enhancement
created: 2026-09-23T22:35:47Z
updated: 2026-09-23T23:01:41Z
closed: 2026-09-23T23:01:41Z
+++

TypedEntityRef.set requires values for the entire queried component pack. A system that changes Position but only reads Velocity must write both through this API, emitting changed events for the unchanged Velocity too. Existing entity handles offer individual writes but lose the typed-row access path. The typed API lacks selective mutation that preserves its type guarantees, component-event behavior, and batched storage observation.

- `2026-09-23T23:01:41Z`: Added typed ComponentRef<Value> handles through row.components. Reading value participates in observation; writing or modifying value emits only that component event and preserves update batching. Tuple reads and whole-row set remain available. Starfall movement now demonstrates selective writes. Tests cover single/multiple component packs, event isolation, and rearming observation.

---

## 23: Query API names obscure snapshot and lazy iteration differences

+++
status: closed
priority: medium
kind: enhancement
created: 2026-09-23T22:35:48Z
updated: 2026-09-23T23:01:41Z
closed: 2026-09-23T23:01:41Z
+++

World.query returns an entity-array snapshot, World.entities exposes lazy entity and fast-reference sequences, and World.typedQuery exposes typed row sequences. These overlapping names do not make the default path or the snapshot-versus-lazy distinction clear. Callers must inspect overloads and return types to understand component access, allocation, and lifetime differences. Review naming and organization while retaining the useful capabilities of each path.

- `2026-09-23T23:01:41Z`: Renamed typedQuery to query as the default typed lazy API. Entity-array snapshots use snapshot(matching:) or snapshot(with:); lazy handles use entities(matching:); the older untyped fast path uses references. Removed old spellings and migrated library tests, benchmarks, demos, and README. Added tests distinguishing fixed snapshot membership from live lazy iteration and documenting that snapshot handles do not freeze component values. All 170 core tests and 15 demo tests pass, Debug/Release and macOS build pass, strict lint is clean. Typed benchmark remains approximately 10.2 ms/100K entities.

---

## 24: Mutation paths separately coordinate storage writes and observation

+++
status: closed
priority: medium
kind: enhancement
labels: effort:m
created: 2026-09-24T01:30:21Z
updated: 2026-09-24T01:57:20Z
closed: 2026-09-24T01:57:20Z
+++

World, ComponentRef, and TypedEntityRef each coordinate storage writes, component events, and Swift Observation invalidation. Update batching also lives in World simulation bookkeeping. Understanding mutation semantics requires following several entry points whose responsibilities overlap.

This creates integration risk when a new write path omits notification, changes event ordering, or interacts with reentrant callbacks. Dependencies are entirely in-process.

Tests currently mix public mutation contracts with direct ObserverRegistry tests. Any architectural change must preserve their subscriber-removal and dispatch coverage at the public boundary, plus coverage across write paths, update batching, and failure handling. Preserve measured cross-module specialization gains. No replacement interface has been selected.

Related: #4 concerns batching across substeps and #5 measures observation overhead. This issue concerns ownership of mutation semantics, not those feature or measurement tasks.

- `2026-09-24T01:57:20Z`: Selected and implemented a World-owned mutation coordinator with inlinable write/event scopes and nested batch scopes. Design recorded in RFC-mutation-scope.md; public API unchanged.
- `2026-09-24T01:57:20Z`: Centralized storage observation, synchronous component-event dispatch, and batch bookkeeping in MutationCoordinator. All entity/component/typed-row/relationship/lifecycle writers use its mutation scope; World.update and recursive deletion share its batch operation. Removed standalone ObserverRegistry and replaced its direct tests with public World boundary tests. Added ordering, reentrant callback, whole-row-before-events, callback deletion, and lifecycle notification coverage. Existing no-op, failed-write, nested/error batch tests pass. 175 core tests pass in Debug/Release, 15 demo tests and macOS build pass, strict lint is clean. Release typed benchmark: baseline 9.628/9.583 ms unobserved/observed; final 9.919/9.931 ms. Small measured increase, specialization gains preserved. #4 public batching across sequential substeps remains separate.

---

## 25: Query evaluation and cache responsibilities are spread across multiple paths

+++
status: closed
priority: medium
kind: enhancement
labels: effort:m
created: 2026-09-24T01:30:21Z
updated: 2026-09-24T02:12:39Z
closed: 2026-09-24T02:12:39Z
+++

Query.swift, Query+Relationships.swift, typed sequences/iterators, and World cache invalidation jointly implement one query contract. Predicates have separate archetype matching, entity-filter classification, and entity-level evaluation. Snapshot and lazy paths coordinate these pieces independently.

Adding predicate kinds or changing caching requires updates across these paths. Missing one can cause incorrect negation, stale membership, or disagreement between query APIs. Dependencies are entirely in-process.

Behavioral coverage must verify boolean combinations, relationship changes, new archetypes, and snapshot/lazy semantics through public query APIs. Compiler feasibility probes serve a different purpose from query behavior tests. No replacement interface has been selected.

Related: #19 measures relationship-query scaling. This issue concerns query ownership and integration risk, not a new caching policy.

- `2026-09-24T02:12:39Z`: Selected and implemented a World-owned QueryEngine. RFC-query-engine.md records the interface, cache ownership, semantics, and test strategy. Public APIs unchanged.
- `2026-09-24T02:12:39Z`: Centralized registered-query cache state, candidate selection, required-component filtering, snapshots, and predicate evaluation in QueryEngine. One tri-state evaluator handles archetype and live-entity evaluation, removing separate relationship classification/evaluation switches. Cache generations are internal; World signals new archetypes. Replaced the smaller negation matrix with a public-boundary matrix across query paths, graph edits, archetype changes, registration cycles, and required components. Added captured-archetype and world-isolation/observation checks. 177 core tests pass in Debug/Release, 15 demo tests and macOS build pass, strict lint passes. Release medians: baseline 9.835/9.850 ms unobserved/observed, engine 9.974/10.048 ms. Relationship-query scaling remains #19.

---

## 26: Relationship policies and lifecycle cleanup have split ownership

+++
status: closed
priority: medium
kind: task
labels: effort:l, area:storage, area:relationships
created: 2026-09-24T01:30:21Z
updated: 2026-09-29T15:17:22Z
closed: 2026-09-29T15:17:22Z
+++

Entity+Relationships enforces cardinality, cycles, and entity validity; RelationshipStorage owns forward/reverse indexes; World cloning and deletion copy or remove links; query predicates read that storage directly. One relationship lifecycle spans these layers.

Correctness depends on every path preserving graph policies, index consistency, cloning/deletion semantics, and observation. Those responsibilities have no single internal owner. Dependencies are entirely in-process.

Existing public relationship tests provide useful boundary coverage. Preserve reparenting, clone behavior, detaching and recursive deletion, rejected mutations, traversal ordering, and observation while considering a deeper boundary. No replacement interface has been selected.

Related: #8 concerns archetype reclamation, #17 explores graph-backed scheduling, and #19 measures relationship workloads. This issue concerns ownership of the existing graph contract.

\- `2026-09-29T14:38:22Z`: Related to #19: relationship performance coverage provides a baseline for changes to graph ownership. This task concerns policy and lifecycle boundaries, not performance measurement alone.
\- `2026-09-29T15:17:22Z`: Consolidated relationship graph ownership behind a single internal RelationshipGraph, without any public behavior change.

Before: the per-type index map (world.relationships: [RelationshipType: RelationshipStorage]) was mutated from several places. Entity+Relationships created RelationshipStorage instances and assigned them back into the map while applying cardinality/cycle/validity policy; World.removeEntity and cloneEntity iterated relationships.values to remove or copy links; QueryEngine read the map directly. No single component owned index consistency or per-type storage lifecycle.

After: RelationshipGraph owns the [RelationshipType: RelationshipStorage] map and is the only code that creates per-type storage and mutates forward/reverse indexes. It exposes reads (targets/sources/contains/traverse/reaches) and pure writes (insert/remove/removeOutgoing/removeEntity/copyOutgoing). Callers no longer touch the map:
- Entity+Relationships expresses cardinality (isExclusive) and cycle (isAcyclic) policy and validity checks on top of graph primitives, still wrapping index writes in world.mutations.perform for observation. No caller constructs RelationshipStorage or assigns into a dictionary anymore.
- World.removeEntity -> relationshipGraph.removeEntity(id); World.cloneEntity -> relationshipGraph.copyOutgoing(from:to:), inside their existing mutation scopes.
- QueryEngine reads via relationshipGraph.contains/reaches.

Owner boundary: RelationshipGraph owns index state and per-type storage; the Entity API owns policy; the mutation coordinator owns observation. This gives one owner of the graph contract while keeping policy and observation where they belong. Low risk: mechanical routing plus one new internal type; no public signatures changed and no policy weakened.

Verification: all existing relationship tests (reparenting, clone, detach, recursive deletion, rejected mutations, traversal order, observation) pass unchanged. Added RelationshipGraphTests boundary coverage: forward/reverse index consistency across mixed non-exclusive edits, isolation between distinct relationship types, entity deletion clearing both directions across types, clone copying outgoing-only with the self-link retargeted to the original, and acyclic cycle rejection preserving existing links and BFS descendant order. Full suite 279 green, 18 demo-support tests green, lint clean. No public behavior change.

---

## 27: Structural command access is too coarse for selective synchronization

+++
status: closed
priority: medium
kind: enhancement
labels: area:systems, area:synchronization
created: 2026-09-28T17:21:00Z
updated: 2026-09-29T14:37:54Z
closed: 2026-09-28T17:45:51Z
+++

Commands() currently reports only SystemAccess.changesStructure. Every command-capable system therefore conflicts with every other system, regardless of the commands it can issue.

The metadata cannot distinguish entity creation or destruction from component-specific or relationship-specific effects. It also cannot express which component sets a creation command can introduce.

Expected: structural effects are explicit and enforceable through the typed command API. Metadata must describe all permitted effects, including relationship cleanup caused by destruction. Unknown or unrestricted effects must remain conservative rather than allow a required synchronization point to be omitted.

- `2026-09-28T17:45:51Z`: Added typed creation, component-edit, relationship-edit, and destruction capabilities with derived command-effect metadata. Unrestricted commands and destruction remain conservative. Runtime tests and external-client compile-failure checks verify the capability boundaries.

---

## 28: System access metadata omits query-matching dependencies

+++
status: closed
priority: medium
kind: enhancement
labels: area:systems, area:synchronization, area:queries
created: 2026-09-28T17:21:09Z
updated: 2026-09-29T14:37:54Z
closed: 2026-09-28T17:45:51Z
+++

SystemQuery records its typed Read and Write terms in SystemAccess, but matching predicates are absent from that metadata. Filters can depend on component presence or absence, relationship edges, and descendant traversal without reading component values.

For example, a system that reads Position while excluding Disabled depends on Disabled membership. A relationship-filtered query can change its result after a queued link change even when none of its component values change. A zero-term query also depends on entity existence.

Expected: dependency metadata accounts for all conditions that can change query membership, including compound predicates and relationship traversal. These dependencies must remain distinguishable from component-value access. Coverage must demonstrate that relevant structural changes cannot be missed when deciding whether synchronization is required.

- `2026-09-28T17:45:51Z`: Added complete query dependencies, including exclusions, compound predicates, creation-signature matching, and relationship traversal. System bindings are frozen at definition time so execution cannot drift from its metadata. Dependency and binding-stability tests pass.

---

## 29: Pipelines flush deferred commands after every system regardless of dependencies

+++
status: closed
priority: medium
kind: feature
labels: area:systems, area:synchronization, area:pipelines
depends: 27, 28
created: 2026-09-28T17:21:21Z
updated: 2026-09-29T14:37:54Z
closed: 2026-09-28T17:45:51Z
+++

Each System execution owns its command buffer and flushes it immediately after its callback. This provides conservative synchronization but prevents commands from remaining pending across unrelated systems. Pipelines have no dependency-aware synchronization plan.

Expected: queued structural changes become visible before a downstream system depends on their effects, without unnecessary intermediate merges. Pending effects must be considered across all systems since the previous merge. Immediate component-value writes must not be confused with deferred structural commands, and a read/write conflict must not invent execution order.

Existing phases, explicit dependencies, registration-order tie breaking, and captured schedules must retain their ordering guarantees. Command order, query-binding timing, callback-scoped references, observer reentrancy, and deferred cleanup must remain safe across merges.

Visibility and failure behavior must be explicit and tested for pipeline completion, empty selections, manual runs, nested runs, callback errors, and command-flush errors. Regression coverage must include creation followed by matching queries, exclusions, relationship traversal, and unrelated systems between a producer and consumer. Measurements must report merge counts and runtime against the current per-system flush behavior.

This issue covers sequential Flecs-style synchronization points, not parallel system execution.

- `2026-09-28T17:45:51Z`: Added automatic pipeline-owned command merging, an afterEachSystem comparison policy, and run statistics. Covered nested runs, reentrant observers, partial flush failures, callback failures, cleanup, and empty selections. Both demos use typed command capabilities. Debug/Release package tests, 15 demo tests, lint, and the macOS demo build pass. Release benchmark: 32 to 1 merges/frame for 4096 commands; median 4.06 ms automatic versus 3.99 ms per-system, with no runtime speedup claimed.

---

## 30: Systems lack an enforceable parallel-execution eligibility contract

+++
status: closed
priority: medium
kind: feature
labels: area:systems, area:concurrency
created: 2026-09-28T19:35:16Z
updated: 2026-09-29T14:37:54Z
closed: 2026-09-28T21:50:53Z
+++

System callbacks and lifecycle hooks can capture arbitrary mutable state. Component only marks data, and the current value-semantics contract does not establish Sendable safety. Read/write declarations describe ECS access, not captured state or executor isolation.

Expected: parallel eligibility has an explicit, compiler-checked contract covering callback captures, component payloads, command payloads, and scoped query access. Actor-isolated and otherwise serial-only systems remain usable without unsafe transfer. Concurrent invocation of the same stateful system, including registration in multiple worlds, must have defined behavior.

The contract must distinguish safe task transfer from exclusive access to live ECS storage. Blanket unchecked Sendable conformances must not substitute for ownership guarantees. Compile-failure coverage must reject unsupported captures and payloads.

This concerns concurrent systems within a world. Off-main simulation ownership and render snapshots remain tracked separately in #15.

- `2026-09-28T21:50:53Z`: Added ConcurrentComponent and ConcurrentRelationship eligibility, Sendable callbacks, transferable input metatypes, and sealed parallel bindings. Serial actor-bound callbacks remain supported. Compile checks reject unsafe captures, payloads, actor-isolated access, unrestricted inputs, and escaped write handles.

---

## 31: Nonconflicting component access still reaches shared mutable world state

+++
status: closed
priority: medium
kind: enhancement
labels: area:concurrency, area:storage
depends: 30
created: 2026-09-28T19:35:28Z
updated: 2026-09-29T14:37:54Z
closed: 2026-09-28T21:50:53Z
+++

Systems with disjoint component declarations still use shared World state, query machinery, and mutation bookkeeping. SystemComponent also falls back to world lookups after a structural revision. A false result from SystemAccess.conflicts is therefore not proof that concurrent callbacks are race-free.

Expected: eligible systems can read shared components and write disjoint component storage concurrently without racing query preparation, arrays, world dictionaries, revision tracking, or shared bookkeeping. Binding, storage lifetime, and exclusive-write ownership must remain valid for the complete execution interval.

Structural changes, world reuse, and external world access must not invalidate storage while a callback is active. Concurrent update/run calls on the same world need an explicit supported or rejected contract. Raw Entity, World, and query-reference APIs must not become implicitly thread-safe.

Coverage must include different components on the same entities, different archetypes, read/read sharing, conflicting writes, and structural access attempts during execution.

- `2026-09-28T21:50:53Z`: Workers use scoped column views without World access. Column access is lock-protected, query preparation stays on the owner, and raw storage access is gated while jobs run. Async runs reject concurrent or nested ownership. Actor ownership, shared reads, disjoint writes, and repeated partition updates pass Thread Sanitizer.

---

## 32: Observers and storage invalidation have no parallel-execution contract

+++
status: closed
priority: medium
kind: enhancement
labels: area:concurrency, area:observation
depends: 30
created: 2026-09-28T19:35:39Z
updated: 2026-09-29T14:37:54Z
closed: 2026-09-28T21:50:53Z
+++

Component observers run synchronously and can access or mutate arbitrary world state. MutationCoordinator maintains shared batching and notification state. Sequential synchronization currently treats observers conservatively, but that does not define safe behavior when several system callbacks execute concurrently.

Expected: observer delivery and storage invalidation have explicit isolation, ordering, and visibility guarantees. Existing synchronous observer behavior must remain supported through a safe serial path unless callers explicitly choose different semantics. Observable publication must not race worker writes or expose partially completed execution.

Reentrant observers, nested runs, observer registration/removal, and callback-triggered structural changes need defined behavior while parallel work exists. Tests must verify notification counts, event ordering, executor expectations, and safe rejection or serialization of unsupported reentrancy.

Render-snapshot publication is separate work in #15; this issue covers the existing ECS observation APIs.

- `2026-09-28T21:50:53Z`: Component observers force owner-isolated serial fallback with synchronous delivery. Storage publication and lifecycle cleanup occur after jobs join. Nested runs during an async execution are rejected; the synchronous runner retains its prior nesting behavior. Observer and cleanup boundary tests pass.

---

## 33: Deferred commands and entity reservations are unsafe for concurrent producers

+++
status: closed
priority: medium
kind: enhancement
labels: area:systems, area:concurrency, area:commands
depends: 30
created: 2026-09-28T19:35:50Z
updated: 2026-09-29T14:37:54Z
closed: 2026-09-28T21:50:53Z
+++

Each callback has a command array, but creation also mutates World.reservedCommandIDs. Deferred operations capture payloads in non-Sendable closures, and PipelineExecution consumes batches in sequential callback order. These assumptions do not support concurrent producers.

Expected: parallel-eligible callbacks can enqueue commands and reserve unique entity identities without shared-state races. Command payload ownership and transfer must satisfy the parallel eligibility contract. Structural application remains exclusive to callback execution.

Merge order must follow a defined logical system order, not task completion order, while preserving order within each callback. Relationships and component edits targeting newly created entities must work across compatible batches. Scheduling variability must not change the logical result for deterministic callbacks, apart from independently generated random identifiers.

Success, cancellation, callback failure, and partial merge failure must release reservations and discard the correct uncommitted commands. No buffer or scoped handle may outlive its permitted execution interval.

- `2026-09-28T21:50:53Z`: Added task-local command buffers, synchronized identity reservations, checked payload transport, and deterministic schedule/partition merge order. Failure commits only the successful logical system prefix; a failed partition discards that entire system command batch. Cancellation, reservations, creation, edits, relationship changes, and cleanup are covered.

---

## 34: Pipelines cannot execute independent eligible systems concurrently

+++
status: closed
priority: medium
kind: feature
labels: area:systems, area:pipelines, area:concurrency
depends: 30, 31, 32, 33
created: 2026-09-28T19:36:03Z
updated: 2026-09-29T14:37:54Z
closed: 2026-09-28T21:50:53Z
+++

PipelineExecution runs every callback serially. Access metadata and sequential merge points exist, but there is no supported parallel execution mode or completion boundary for a group of concurrent callbacks.

Expected: independent parallel-eligible systems can overlap while serial-only systems remain supported. Scheduling must respect component conflicts, complete query dependencies, command effects, phases, explicit dependencies, and captured schedules. The sequential reference order must resolve otherwise unordered conflicts without inventing producer/consumer semantics. Ready nonconflicting systems may overlap without weakening required ordering.

All callbacks using storage must finish before a structural merge, cleanup, or storage reuse. Concurrency must be bounded. Manual runs, nested runs, and simultaneous calls on a world need defined behavior rather than accidental reentrancy.

Cancellation and one or more callback failures must have explicit semantics for joining active work, selecting reported errors, retaining immediate writes, committing successful command batches, and releasing scopes. The run must not return while work still accesses its world.

Existing synchronous serial execution remains supported. This issue covers parallel systems, not subdivision of one system query.

- `2026-09-28T21:50:53Z`: Added async World update/run overloads with a bounded structured executor and conflict/dependency/phase-aware groups. Serial-only systems and observers retain serial execution. All jobs join before errors, merges, or cleanup; errors use logical order and cancellation is cooperative. Concurrent ownership is rejected and execution statistics report groups and jobs.

---

## 35: Parallel execution lacks race validation and scaling measurements

+++
status: closed
priority: medium
kind: task
labels: area:concurrency, area:testing, area:performance
depends: 34
created: 2026-09-28T19:36:14Z
updated: 2026-09-29T14:37:54Z
closed: 2026-09-28T21:50:53Z
+++

The existing tests and synchronization benchmark validate sequential execution. They do not establish race freedom, actual callback overlap, bounded concurrency, serial equivalence, or useful scaling for parallel systems.

Expected: strict Swift concurrency checks and compile-failure fixtures enforce eligibility boundaries. Thread Sanitizer stress coverage exercises storage access, command reservations, observers, cancellation, multiple failures, nested execution, and cleanup. Deterministic synchronization in tests must demonstrate overlap for independent systems and exclusion for conflicting systems without relying on sleeps.

Serial and parallel executions must produce equivalent logical results for deterministic workloads across repeated scheduling variations and worker counts. Parallel-capable demo scenarios must retain their behavior, including serial-only fallbacks.

Measurements must compare the serial baseline with several concurrency limits and workload sizes. Include compute-heavy, memory-bound, highly conflicting, and command-heavy cases; report runtime, scheduling overhead, merge counts, and small-workload regressions. Record the hardware and build configuration, and do not infer a speedup from overlap alone.

- `2026-09-28T21:50:53Z`: Added compile-failure fixtures, deterministic overlap/bound tests, stress comparisons, and a workload benchmark covering idle, compute, memory, conflicts, commands, and partitions at multiple sizes and limits. The 253-test package suite passes Debug, Release, and Thread Sanitizer; 18 demo tests and macOS/iOS simulator builds pass. Recorded M5 Max measurements show compute gains but memory/conflict/command regressions and nonzero serial overhead; no universal speedup claim.

---

## 36: A single large system query cannot use parallel entity iteration

+++
status: closed
priority: low
kind: feature
labels: area:systems, area:queries, area:concurrency
depends: 34, 35
created: 2026-09-28T19:36:25Z
updated: 2026-09-29T14:37:54Z
closed: 2026-09-28T21:50:53Z
+++

Parallel execution of independent systems cannot accelerate a workload dominated by one large query. SystemRows currently exposes a sequential iterator, and its access contract grants component-type access rather than disjoint row ownership.

Expected: a separately eligible per-entity callback can process disjoint portions of one query concurrently without duplicate or omitted entities, overlapping writable rows, escaped references, or races in shared array storage. Stateful callbacks, cross-entity access, and reductions need explicit supported or rejected contracts.

Command ordering, filtering, cancellation, errors, and completion before structural merges must remain defined across partitions. Validation must cover uneven archetype sizes, empty matches, component sharing, deterministic results, and partitioning overhead.

This is a later follow-up to validated parallel-system execution, not a requirement for its first release.

- `2026-09-28T21:50:53Z`: Added eachParallel with disjoint prepared row ranges, minimum partition sizes, and a global concurrency bound. Partition callbacks receive only their row and sealed command capabilities; additional mutable queries cannot be disguised as command inputs. Empty/uneven/filtered archetypes, exact coverage, command order, partition failure, serial equivalence, and partitioning costs are tested. Stateful/order-dependent reductions remain explicitly serial or caller-synchronized.

---

## 37: Typed serial movement is substantially slower than direct component references

+++
status: closed
priority: high
kind: bug
labels: area:systems, area:performance
created: 2026-09-29T02:11:25Z
updated: 2026-09-29T14:37:54Z
closed: 2026-09-29T04:02:55Z
+++

The Release 100,000-entity movement comparison measures 77.28 ms/frame for the typed serial system versus 17.25 ms/frame for the original component-reference loop. Both apply the same XYZ movement math and three component writes per entity. Full-state verification passes.

Reproduce with ECS_RUN_MOVEMENT_BENCHMARKS=1 xcb test SwiftECS/SwiftECS -c release -- --filter MovementParallelBenchmarkTests. Results are three-round medians with three warm-up frames and 60 measured frames, on Apple M5 Max and macOS 27.0.

Expected: type-safe system access should not impose this large per-entity overhead. Profile the actual hot path and retain matching, reference lifetime, observer, and mutation semantics while addressing the regression.

- `2026-09-29T04:02:55Z`: Profiled Release movement with sample. Generic/tuple metadata and repeated exclusivity checks dominated serial access. Bound field accessors once, specialized iteration over resolved output types, and kept lifetime/revision checks in non-Sendable owner-local cells. Three-round 100K median improved from 77.28 to 12.50 ms/frame; raw reference loop measured 14.68 ms. Full-state verification and 260 tests pass. Evidence and reproduction are in Experiments/ParallelMovementProfiling.md.
- `2026-09-29T04:24:01Z`: Documentation cleanup preserved the profiling evidence here: an 8-second serial sample had 5946 main-thread samples, 5743 beneath movement, with generic/tuple metadata operations prominent under iteration, term resolution, and component access. After specialization, repeated dynamic exclusivity checks on owner-local state became prominent. Current benchmarks and Scripts/profile-movement.fish reproduce the workload; the README retains measurement methodology and before/after results. The retired detailed report remains in version control.

---

## 38: Partitioned movement slows down as workers contend on fine-grained access

+++
status: closed
priority: high
kind: bug
labels: area:concurrency, area:performance
created: 2026-09-29T02:11:25Z
updated: 2026-09-29T14:37:54Z
closed: 2026-09-29T04:02:55Z
+++

The Release 100,000-entity movement comparison measures 153.46, 116.59, and 153.46 ms/frame with 2, 4, and 8 jobs, respectively, versus 77.28 ms/frame for the same typed callback executed serially. The original raw loop measures 17.25 ms/frame.

Current component access locks the column and worker bookkeeping for individual operations, even when partitions own distinct rows. Lock contention is a suspected contributor, not yet a profiled conclusion.

Reproduce with ECS_RUN_MOVEMENT_BENCHMARKS=1 xcb test SwiftECS/SwiftECS -c release -- --filter MovementParallelBenchmarkTests on Apple M5 Max, macOS 27.0. All results pass full-state verification.

Expected: disjoint row processing should avoid per-element synchronization overhead that defeats parallel execution. Changes must retain ownership boundaries, deterministic command merges, cancellation cleanup, observer fallback, and race freedom. Validate with profiles, repeated benchmarks, compile-failure checks, and Thread Sanitizer.

- `2026-09-29T04:02:55Z`: The four-job profile confirmed column-lock waits and metadata overhead. Workers now use task-owned buffers with shared per-task query aliases and dirty-only writeback after joining, before structural merges. Failure writeback and command-prefix behavior remain covered. 100K medians improved from 116.59 to 7.97 ms with four jobs and from 153.46 to 6.45 ms with eight. Debug/Release tests, Thread Sanitizer, Address Sanitizer, compile checks, demo tests, macOS/iOS builds, and lint pass. No new unchecked-Sendable buffer or owner-cell wrappers were introduced.
- `2026-09-29T04:24:01Z`: Documentation cleanup preserved the original four-job profile evidence: top-of-stack sample counts included 1931 in __ulock_wait2, 718 in __ulock_wake, and 1969 in generic tuple-cache lookup/insertion. These are samples across threads, not frame-time percentages. The post-fix profile no longer showed element-lock waits among hot stacks; remaining costs included reference counting, arrays, buffer preparation, and iteration. Scripts/profile-movement.fish waits for a PID file after warm-up and stores raw profiles/logs in its printed /tmp directory. Compare performance using separate unprofiled runs. Further scaling work remains in #39–#41.

---

## 39: Movement scaling beyond eight jobs and limiting phases are unmeasured

+++
status: closed
priority: medium
kind: task
labels: effort:m, area:performance, area:concurrency, area:scaling
created: 2026-09-29T04:18:27Z
updated: 2026-09-29T14:52:33Z
closed: 2026-09-29T14:52:33Z
+++

The corrected 100,000-entity movement benchmark measures 12.50 ms/frame serial, 10.56 ms with two jobs, 7.97 ms with four, and 6.45 ms with eight. Eight jobs provide about 1.94x speedup over the same typed serial path. The test host reports 18 logical processors, but limits above eight have not been measured. These data do not establish a scaling ceiling or explain the remaining limit.

Expected: repeated Release measurements cover concurrency limits through the available processor count, including 12, 16, and 18 on this host. Include several entity counts and per-entity compute costs, with identical work and full-state verification. Report speedup, parallel efficiency, variability, and the best observed limit rather than assuming linear scaling.

Separate end-to-end time into schedule/query preparation, task dispatch and execution, joining, value writeback, and command merging. Distinguish configured concurrency, job count, and observed overlap/utilization. Record CPU topology, toolchain, hardware, and build configuration; logical processors are not interchangeable dedicated worker threads.

This extends the initial validation in #35 and the fixes in #37/#38. Profiled runs must remain separate from benchmark timings.

\- `2026-09-29T14:38:22Z`: Related to #40, #41, and #42. #40 and #41 depend on this phase-level scaling evidence before addressing buffer/writeback and partition/dispatch costs. #42 separately varies system/phase graph size rather than movement entity count.
\- `2026-09-29T14:52:33Z`: Added opt-in MovementScalingBenchmarkTests (ECS_RUN_SCALING_BENCHMARKS=1) sweeping job limits 1,2,4,8,12,16,18 across entity counts with full-state verification each sample, reporting speedup, parallel efficiency, and best observed limit. Overridable via ECS_SCALING_ENTITIES/LIMITS/ROUNDS/FRAMES/ITERATIONS.

Measured Apple M5 Max (18 processors), macOS 27.0 (26A428), Swift 6.4, Release; rounds=2, frames=20, one movement system:

100,000 entities (ms/frame, speedup, efficiency): limit1 8.31/1.00x/1.00; 2 21.06/0.40x/0.20; 4 11.97/0.69x/0.17; 8 8.22/1.01x/0.13; 12 7.32/1.14x/0.10; 16 7.18/1.16x/0.07; 18 6.60/1.26x/0.07. Best 18 jobs, 1.26x.

1,000,000 entities: limit1 82.04/1.00x; 2 64.26/1.28x/0.64; 4 43.33/1.89x/0.47; 8 69.78/1.18x/0.15; 12 69.97/1.17x; 16 70.10/1.17x; 18 67.51/1.22x. Best 4 jobs, 1.89x, regressing beyond four.

Compute-heavy control (ECS_SCALING_ITERATIONS=200, 100k): 8 jobs 1.84x, 16 jobs 2.11x. Raising per-entity work improves scaling, confirming the light movement workload is memory-bandwidth bound rather than framework-bound.

Findings: this workload does not scale to the 18 logical processors; efficiency falls steadily and more jobs never approach linear. The 1M case regressing past four jobs indicates memory-bandwidth saturation. Low-round runs show notable variance (e.g. the 100k limit=2 spike); raise ECS_SCALING_ROUNDS for stability.

Phase-level breakdown (schedule/query prep, dispatch, join, writeback, command merge) needs invasive core instrumentation and is deferred to #40 (snapshot/writeback) and #41 (partition/dispatch), which build on this baseline. lastRunStatistics job/batch/merge counters are asserted in the benchmark. Profiled runs stay separate from these benchmark timings. README updated with the command and headline results.

---

## 40: Snapshot and writeback costs are not isolated in parallel scaling results

+++
status: closed
priority: medium
kind: task
labels: effort:l, area:storage, area:performance, area:scaling
depends: 39
created: 2026-09-29T04:18:45Z
updated: 2026-09-29T15:23:12Z
closed: 2026-09-29T15:23:12Z
+++

Parallel queries use snapshots and task-owned buffers. Partition preparation allocates selected rows and index mappings; writes maintain dirty masks, and the owner applies updates after all jobs join. These costs remain even after per-element worker locks were removed. Their contribution to current frame time and memory-bandwidth pressure has not been quantified separately.

Expected: measurements identify bytes copied, allocations, peak temporary memory, dirty-mask scanning, and owner-side writeback time as entity count, component size, write density, archetype count, and job count vary. Read-only, sparse-write, and full-write workloads need distinct results, including overlapping queries within one task.

Avoidable costs established by these measurements must be reduced without restoring per-element contention or weakening ownership. Preserve task-local read-after-write behavior, disjoint partitions, dirty-only updates, writes from failed callbacks, command-prefix semantics, and observer fallback. Any optimization must retain compile-time capability checks and sanitizer coverage.

Copying and serial writeback are candidates for investigation, not established explanations for the observed 1.94x movement speedup.

\- `2026-09-29T14:38:22Z`: Related to #39: use its phase-level scaling results as the baseline. This issue adds buffer/allocation/write-density measurements and addresses costs established by them; it is not a duplicate of the overall scaling sweep.
\- `2026-09-29T15:23:12Z`: Checked #39 first (uniform movement is memory-bandwidth bound). Added opt-in ParallelBufferBenchmarkTests (ECS_RUN_BUFFER_BENCHMARKS=1) isolating snapshot copy, dirty-mask, and writeback across component size, write density, archetype count, and job count, including read-only and overlapping queries. Effects verified outside timing; overridable via ECS_BUF_ENTITIES/ROUNDS/FRAMES/LIMIT.

Measured Apple M5 Max (18 processors), macOS 27.0 (26A428), Swift 6.4, Release; 200,000 entities, rounds=3, frames=10, limit=8 medians (ms/frame):

- read-only small (8B) 4.79; read-only wide (64B) 4.80. Snapshot+slice copy for reads is not bandwidth-bound at this size: 8x the bytes cost the same time, so per-row iteration/dispatch dominates reads, not copy volume.
- write-full-small: parallel 7.86 vs serial 8.90 (parallel wins modestly).
- write-full-wide (64B): parallel 9.61 vs serial 8.94 (parallel LOSES). The whole-column snapshot + per-partition slice + writeback triple-copies the large payload (~3N x 64B) versus serial in-place (~N), so large components regress under parallel. This is the clearest isolated snapshot/writeback cost.
- write-sparse-small (1% written): parallel 2.11 vs serial 4.00. Dirty-only writeback keeps sparse writes cheap; the mask pays off.
- job sweep (full-write small): 1 -> 8.79, 4 -> 7.15, 8 -> 7.63. Best near 4 jobs; 8 regresses, matching the #39 memory-bound ceiling.
- archetype spread: 64 buckets 7.92 vs 1 bucket 7.68. Many small batches add slight snapshot/binding overhead, but modest.
- overlapping-shared-buffer 9.27. Reads and writes over the same column share one task buffer (keyed by column), so overlapping queries do not double-snapshot.

Avoidable cost identified: the redundant intermediate whole-column snapshot. Each prepared query copies the entire column once (ParallelColumnSnapshot.init -> column.snapshot()), then every partition copies its slice again from that snapshot. For large components this doubles read-side copy (2N) on top of writeback (N). The safe fix is to drop the whole-column snapshot and have each partition bulk-copy only its slice directly from the live column under a single lock (no per-element contention; the live column is immutable during the parallel phase). Read-only columns could further avoid a write buffer/dirty-mask entirely.

Why not implemented here: that change rewrites the concurrency hot path (ParallelColumnSnapshot / ParallelQueryStorage / TaskColumn, plus a bulk Column copyRange) with read-after-write, overlapping-buffer-sharing, dense/sparse index-mapping, and writeback correctness to preserve, and needs its own TSan-verified design. It is not a clearly-safe same-session micro-fix, and small-component workloads already benefit, so it is recorded as scoped follow-up rather than risked now. No per-element contention was introduced and ownership is unchanged.

Verification: full suite 280 green; TSan clean on the parallel suites; all 14 concurrency compile checks pass; lint clean. No production code changed. README updated with the command and headline results. Related: #39 (uniform scaling ceiling), #41 (partition/dispatch).

---

## 41: Row-count partitioning does not account for uneven work or dispatch cost

+++
status: closed
priority: medium
kind: enhancement
labels: effort:l, area:performance, area:scaling, area:scheduling
depends: 39
created: 2026-09-29T04:19:01Z
updated: 2026-09-29T15:13:52Z
closed: 2026-09-29T15:13:52Z
+++

eachParallel divides matching rows into fixed ranges and caps the partition count at the concurrency limit. minimumRowsPerTask considers row count, not actual computation or differences in executor throughput. Equal-sized ranges can therefore contain unequal work, and small jobs can cost more to dispatch than to execute. Current measurements do not isolate partition tail latency, idle capacity, or the break-even point for parallel execution.

Expected: scaling coverage includes skewed per-entity costs, mixed archetype sizes, several ready systems, filters, and small workloads. Report per-job duration, last-job tail time, observed utilization, and dispatch/join overhead across partition sizes and concurrency limits.

Address demonstrated imbalance or excess overhead while keeping active concurrency bounded. Preserve exact row coverage, exclusive writable ownership, query matching, explicit ordering constraints, logical command order, deterministic error selection, cancellation cleanup, and complete joins before storage reuse.

The runtime owns thread and core assignment. More jobs are not evidence of more CPU utilization, and no fixed thread-per-core mapping or universal speedup is assumed.

\- `2026-09-29T14:38:22Z`: Related to #39: use its scaling measurements as the baseline. This issue isolates skewed work, tail latency, partition sizes, and dispatch/join costs rather than just varying worker count.
\- `2026-09-29T15:13:52Z`: Checked #39 first: it measured uniform (memory-bound) movement, not skew or dispatch, which are exactly what #41 asked to isolate. Added an opt-in benchmark (ParallelPartitionBenchmarkTests, ECS_RUN_PARTITION_BENCHMARKS=1) that isolates skew tail latency and dispatch break-even, and implemented a bounded, opt-in over-decomposition knob.

Fix: eachParallel gains tasksPerWorker (default 1). Partitions become min(parallelism * tasksPerWorker, 1 + (count-1)/minimumRowsPerTask). Default (1) is byte-for-byte the previous behavior. Values above one create more, smaller partitions that the existing bounded task group load-balances across at most 'parallelism' active workers. Invariants preserved: exact disjoint row coverage, exclusive writable ownership, prepared-order command merge, deterministic lowest-index error selection, cancellation cleanup, and complete joins before writeback. Validation rejects tasksPerWorker <= 0 with SystemError.invalidPartitionSize.

Regression tests (ParallelPartitionTests): default uses one partition per worker; over-decomposition marks every row exactly once in prepared order (count and Set both 4000, markers == snapshot order) with parallelTaskCount == 16; the row floor still caps partitions (10 rows, minRows 8, tpw 8 -> 2 partitions); a failing over-decomposed partition discards the whole system's command batch while immediate writes remain and reservations release. Full suite (274) green; TSan clean on the parallel suites; lint clean.

Measurements (Apple M5 Max, macOS 27.0, Swift 6.4, Release; limit=8):
Skew tail latency (100k rows, per-row cost rising with index):
- serial 121.9 ms/frame.
- tasksPerWorker=1 (8 fixed partitions): 31.5 ms, 3.87x. The heaviest equal-sized range is the straggler.
- tasksPerWorker=4 (32): 23.1 ms, 5.28x.
- tasksPerWorker=8 (64): 22.2 ms, 5.50x (best).
- tasksPerWorker=16 (128): 22.5 ms, 5.43x (overhead outweighs further balancing).
Over-decomposition cuts skewed frame time ~30% (31.5 -> 22.2 ms) and lifts speedup from 3.87x to 5.50x.

Dispatch break-even (uniform tiny work, serial vs parallel limit=8): entities 64/256/1024/4096 stay serial-favoured (parallel ~0.65-0.74 ms fixed floor); crossover near 16384 (0.797 vs 0.800 ms, ~1.0x); 65536 uniform still slightly favours serial (2.99 vs 3.48 ms), consistent with the memory-bandwidth bound from #39. So parallel has a ~0.7 ms dispatch floor and pays off only above roughly 16k rows with enough per-row work.

Conclusion: the imbalance is real and the opt-in knob addresses it without changing defaults or adding unbounded concurrency. A work-aware automatic split would need per-row cost estimates the framework does not have; the manual knob plus these baselines is the bounded, safe improvement. README documents tasksPerWorker and the results. Related: #39 (uniform scaling), #40 (snapshot/writeback costs).

---

## 42: Large phase graphs have no schedule-resolution cost measurements

+++
status: closed
priority: medium
kind: task
labels: effort:m, area:performance, area:scheduling
created: 2026-09-29T04:23:03Z
updated: 2026-09-29T15:05:55Z
closed: 2026-09-29T15:05:55Z
+++

The scheduler resolves a fresh schedule for each execution and execution-order inspection. It materializes phase-implied system dependencies, including transitive phase ancestors, and repeatedly scans remaining systems during topological ordering. Large phase graphs can therefore require quadratic work and storage. The existing movement benchmarks do not isolate this case.

Expected: dedicated measurements cover increasing system and phase counts, sparse and dense dependencies, long chains, wide phase DAGs, empty intermediary phases, subset pipelines, and frequent runtime edits. Separate graph construction, ordering, allocation, and callback time. Verify schedule and validation results outside timing.

Preserve registration-order tie breaking, explicit dependency errors, phase reachability, captured schedules, and parallel predecessor constraints. Measurements must establish whether schedule resolution is a material limit before choosing caching or another optimization.

Extracted from the retired phases-and-pipelines notes. Related to #39, which measures full execution phases for movement workloads.

\- `2026-09-29T14:38:22Z`: Related to #39 and #19: #39 measures end-to-end movement phases, while #19 measures relationship operations. This issue isolates schedule construction and ordering as system/phase graph size and density grow.
\- `2026-09-29T15:05:55Z`: Added opt-in ScheduleResolutionBenchmarkTests (ECS_RUN_SCHEDULE_BENCHMARKS=1). It isolates schedule construction/ordering via executionOrder(for:) (no callbacks) from dispatch, and verifies resolved schedule sizes outside timing. Overridable via ECS_SCHED_ROUNDS/REPEATS/COUNTS.

Measured Apple M5 Max (18 processors), macOS 27.0 (26A428), Swift 6.4, Release; rounds=3, repeats=20, medians per resolve:

Flat scaling (default phase, N systems): 250 -> 2.165; 500 -> 7.340; 1000 -> 25.685; 2000 -> 95.917 ms. Doubling N multiplies time ~3.3-3.7x -> superlinear, ~O(N^2).

Graph shapes at scale:
- system-chain 2000 (dense linear deps): 127.9 ms, worse than flat-2000.
- phase-chain 500 phases x 2 systems (1000 systems): 89.4 ms, far more than flat-1000 (25.7) at equal system count, because each system materializes/unions all transitive phase-ancestor members.
- wide-dag 500 phases on one root: 28.0 ms (shallow, cheaper).
- empty-intermediary 500 phases, 2 systems: 5.6 ms (traversing empty phases is cheap relative to system count).
- subset-pipeline 2000 systems, query selects 1000: 26.5 ms, matching flat-1000; selection limits work to the selected set.

Resolution vs run: resolve-only 2000 = 100.1 ms; run-noop 2000 = 98.8 ms. A no-op run is essentially all resolution; callback dispatch is negligible for large graphs.

Is resolution a material cost? Yes, but only for large schedules. It is superlinear and re-run on every execution and every executionOrder inspection with no cache. The dominant terms are the Kahn ordering's linear rescans (orderedSystems firstIndex-where-deps-empty per removal) and transitive phase-ancestor member unions. For typical game schedules (tens of systems) resolution is sub-millisecond and irrelevant. A cached schedule (invalidated on query membership and DependsOn/InPhase edits) would help large or subset-heavy pipelines; whether that complexity is warranted is a separate decision, now backed by these numbers. No production code changed. README updated. Related: #39 (end-to-end movement phases), #19 (relationship traversal costs).

---

## 43: Inherited component lookup has no agreed semantics

+++
status: open
priority: low
kind: task
labels: idea, effort:m, area:queries, area:relationships
created: 2026-09-29T04:23:03Z
updated: 2026-09-29T14:37:54Z
+++

The retired Flecs RFC identified ancestor/inherited component lookup as a possible extension. Current relationship queries select linked entities, but component reads do not inherit values from related entities. There is no agreed use case or lookup contract.

An evaluation needs to establish lookup direction, relationship selection, precedence between local and inherited values, multiple-parent ambiguity, and cycle behavior. It must also account for overrides, writes, removal, query matching, observation, and system access/synchronization metadata. Traversal order alone is not an inheritance policy.

Expected: a bounded design decision that distinguishes useful inherited lookup from explicit application traversal. This is an exploratory idea, not approval to implement inheritance, relationship payloads, or a general graph framework. Singleton state remains separate in #18.

- `2026-09-29T14:37:53Z`: Triage: effort:m covers the inheritance use-case and semantics investigation only. Implementation remains a separate decision.
- `2026-09-29T14:38:22Z`: Related to #18: inherited component lookup is distinct from singleton identity and storage. Neither exploration approves implementation of the other.

---

## 44: Declared Swift 6.2 compatibility remains unverified

+++
status: open
priority: medium
kind: task
labels: effort:m, area:testing, area:compatibility
created: 2026-09-29T04:23:03Z
updated: 2026-09-29T15:07:04Z
+++

Package.swift declares Swift tools 6.2, while the retained typed-query investigation and recent concurrency validation used Apple Swift 6.4. The old notes explicitly left Swift 6.2 compatibility unverified. Parameter-pack and concurrency-heavy APIs now depend on this untested minimum.

Expected: establish whether the public APIs, Debug/Release suites, and concurrency compile checks work on the declared minimum toolchain. Record actual compiler versions and distinguish compiler defects from supported-API failures. Keep the declared minimum consistent with verified support.

The standalone compiler probe remains at Experiments/TypedQueryPacks/Probe.swift. Run xcrun swift Experiments/TypedQueryPacks/Probe.swift for the working variant. Historical Swift 6.4 negative variants use -D DIRECT_ACCESS and -D SINGLE_ASSIGNMENT. They reported, respectively:

error: failed to produce diagnostic for expression; please submit a bug report (https://swift.org/contributing/#reporting-bugs)

error: cannot assign value of type 'Position' to type 'Position'

Generic read helpers and the variadic setter avoided those errors. These historical observations are not new verification of another compiler. ECS coverage remains in TypedQueryPackTests, and Scripts/check-concurrency.fish checks the parallel API boundaries. This extends the minimum-toolchain gap left by closed investigation #7.

\- `2026-09-29T15:07:04Z`: Punting: full Swift 6.2 verification is not possible on this machine, and neither remedy in the task is warranted.

Verified on Swift 6.4 (swiftlang-6.4.0.34.1, Xcode 27.0 selected; 27.1/27.2 and swift-latest.xctoolchain are also 6.4):
- Toolchains: no Swift 6.2 or 6.3 toolchain is installed (xcode-select lists only 27.0/27.1/27.2, all Swift 6.4; /Library/Developer/Toolchains has only swift-latest -> 6.4). A 6.2 compiler cannot be exercised here.
- Standalone probe behaves as documented: xcrun swift Experiments/TypedQueryPacks/Probe.swift succeeds (exit 0); -D DIRECT_ACCESS fails ('failed to produce diagnostic for expression'); -D SINGLE_ASSIGNMENT fails ('cannot assign value of type Position to type Position'). Matches the recorded 6.4 behavior.
- Feature-floor analysis of Sources: the parallel APIs use SendableMetatype (ParallelSystemInput, ConcurrentRelationship) and @concurrent (ParallelExecutor), both introduced in Swift 6.2, plus isolated (any Actor)? = #isolation and typed throws(E) (6.0). No 6.3/6.4-only constructs are present (no 'sending', '~Copyable', '~Escapable', or newer syntax). The full Debug/Release suites and Scripts/check-concurrency.fish pass on 6.4.

Conclusion: the declared swift-tools-version: 6.2 is consistent with the code's actual requirements, not an arbitrary untested number - the concurrency surface genuinely needs 6.2 features and would not build on 6.0/6.1. Nothing indicates a need for >6.2, so bumping the minimum to 6.4 (task option a) would be incorrect and over-restrictive; not doing it. Claiming verified 6.2 support without a 6.2 compiler would be guessing (task option: avoid), so not doing that either.

Unblocker: install a Swift 6.2 (and ideally 6.3) toolchain, then run 'xcb test SwiftECS/SwiftECS' (Debug and Release), 'fish Scripts/check-concurrency.fish', and the probe under that toolchain to confirm the public APIs, suites, and compile-failure fixtures behave. Only then can the 6.2 floor be marked verified (or adjusted to the lowest toolchain that actually builds). Leaving the issue open.

---

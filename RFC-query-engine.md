# World-owned query engine (#25)

Status: Implemented.

## Problem

Predicate evaluation, relationship filtering, archetype caching, and query execution have separate owners. Each predicate case requires several classifications and evaluators to agree.

Snapshots bypass the registered-query selection path. Typed queries apply their component requirements separately. This creates seams where new predicates or invalidation changes can produce inconsistent results.

## Chosen interface

World owns an internal QueryEngine. Public query APIs remain unchanged.

```swift
let selection = queries.prepare(query, requiring: componentTypes, in: world)
let entities = queries.snapshot(query, in: world)
let matches = queries.matches(predicate, entityID: id, in: world)
```

Selection returns candidate archetypes and an optional per-entity predicate. One evaluator produces yes, no, or requires-entity results. Without an entity, relationship terms remain unknown, including under negation. With an entity, the same evaluator reads current links.

Snapshots and both lazy paths use this selection process. Typed column binding and row access remain specialized. Component-only queries have no per-entity predicate.

## Cache ownership

The engine owns registration and cache entries. World signals archetype changes after creating new storage. The engine owns its generation counter and rebuilds registered selections after invalidation.

Caches contain archetype selections, never relationship result sets. Relationship edits need no cache invalidation because filtering reads live links. Typed component requirements refine the selected archetypes without altering the registered query.

Lazy sequences retain the archetypes selected at creation. New sequences discover new archetypes. Existing snapshot membership remains fixed, while its entity handles still access live components.

## Dependencies and constraints

All dependencies are in-process: World storage and relationships. The engine does not retain World. It receives World for each operation.

The public facade and iterators retain storage-observation access. Empty and missing results must stay observable. Structural mutation retains existing lifetime restrictions.

This is not a transitive relationship cache or a live result index. Those remain separate performance/design work.

## Tests

Keep existing public query behavior tests. Replace the smaller relationship-negation matrix with a shared boundary matrix covering snapshot, lazy handles, and typed rows, with and without registration.

Verify nested boolean predicates, required components, relationship edits, new archetypes, unregister/re-register, world isolation, and observation. Compiler probes remain separate.

Run Debug/Release tests, demo checks, and the typed-query Release benchmark against a measured baseline. No tests need to inspect cache entries or generation counters.

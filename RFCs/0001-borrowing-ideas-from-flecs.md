# RFC 0001: Borrowing Ideas from flecs

Status: Draft

## Context

[flecs](https://www.flecs.dev/) ([GitHub](https://github.com/SanderMertens/flecs))
is a mature, fast C/C++ ECS. It has design ideas worth adopting in this
project. This RFC captures the ones that look most valuable.

References:

- flecs manual: https://www.flecs.dev/flecs/md_docs_2Manual.html
- Relationships: https://www.flecs.dev/flecs/md_docs_2Relationships.html
- Systems & pipelines: https://www.flecs.dev/flecs/md_docs_2Systems.html
- Query DSL / flecs query manual: https://www.flecs.dev/flecs/md_docs_2Queries.html

## Interesting ideas

### 1. System ordering as ECS data (the big one)

flecs does not schedule systems with a bespoke dependency graph. Ordering
is modeled *inside* the ECS, using the same machinery as everything else:

- **Phases are entities.** The built-in phases (`OnLoad → PostLoad →
  PreUpdate → OnUpdate → OnValidate → PostUpdate → PreStore → OnStore`) are
  just entities in the world.
- **Order is a relationship.** Phases are chained with a `DependsOn`
  relationship between phase entities. Run order is a graph *stored in the
  ECS*, not scheduler-private state.
- **A pipeline is a query.** It matches system entities and walks the
  `DependsOn` graph (cascade traversal) to resolve run order.
- **Composable.** Because phases and pipelines are entities+relationships
  you get custom phases, custom pipelines (a subset of systems), runtime
  pipeline swapping, and running one pipeline independently (e.g. REST/stats
  services separate from gameplay) essentially for free.

Contrast with our current design: an explicit `SystemEntry.dependencies`
list plus a Swift-side topological sort (`systemOrder`). Simple and direct,
but ordering lives outside the data model and custom pipelines are extra
work.

**Proposal:** model phases as entities and dependencies as a relationship,
then resolve order via a query rather than a hand-written topo-sort. Keep a
simple `before:`/`after:` sugar on top for per-system ordering.

### 2. Relationships / pairs

flecs entities can hold **pairs** `(Relation, Target)` — e.g.
`(ChildOf, parent)`, `(Likes, alice)`. This one primitive gives hierarchies,
graphs, and typed links without bespoke component types, and queries can
traverse them (`up`, `cascade`, `descend`).

**Proposal:** evaluate adding a pair/relationship primitive. Even a minimal
`ChildOf` would let us express hierarchies and cascade traversal in queries.

### 3. Singletons

flecs treats a singleton as a component on a well-known entity, so global
state uses the same storage/query path as everything else instead of a
side-channel.

**Proposal:** offer `world.set(singleton:)` / `world.get(Singleton.self)`
backed by the normal component store.

### 4. Query traversal & caching

flecs queries support relationship traversal (matching up a `ChildOf`
chain) and cached vs. uncached queries. We already cache registered queries;
traversal is the missing capability and pairs with idea #2.

## Non-goals

- Not adopting flecs' POD-only component constraint. Native Swift components
  (including non-`BitwiseCopyable` types) stay a core advantage of this
  project.
- Not wrapping the C library. This is about borrowing *design*, not code.

## Open questions

- How much of the relationship model do we want before it stops paying for
  its complexity?
- Do phases-as-entities complicate the `@Observable` SwiftUI story?

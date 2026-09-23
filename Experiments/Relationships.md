# Relationship decisions (#16)

The initial implementation uses general typed relationship pairs. It does not replace the scheduler or implement pipelines (#17).

## Model

A relationship is a marker type conforming to `Relationship`. A source entity holds a link identified by the relationship type and target entity ID.

Links have no payload. Their storage is separate from component columns, so link changes do not move entities between archetypes. Component enumeration does not include links.

Default relationships allow multiple targets, self-links, and cycles. `isExclusive` limits a source to one target per relationship type. Adding another target replaces the previous one.

`isAcyclic` rejects links that introduce cycles, including self-links. Cycle checks run before replacement, so rejected changes leave existing links intact. Relationship policies must remain stable.

`ChildOf` is exclusive and acyclic. Each child has at most one parent. Parents can have multiple children.

## Current API

```swift
enum Likes: Relationship {}

try child.addRelationship(Likes.self, to: friend)
try child.setParent(parent)

child.parent
parent.children
child.targets(of: Likes.self)
friend.sources(of: Likes.self)
child.hasRelationship(Likes.self, to: friend)

try child.removeRelationship(Likes.self, to: friend)
try child.setParent(nil)
```

Writes reject dead entities and cross-world links with `RelationshipError`. Duplicate additions and absent removals do not change storage or notify observation.

## Traversal

`ancestors()` follows `ChildOf` targets. `descendants()` follows incoming `ChildOf` links. Both accept another relationship type through `via:`.

Traversal is breadth-first and follows link insertion order. Each entity appears at most once, and the root is excluded. Iterative walks terminate on cycles without recursive stack growth.

For a ChildOf tree, descendants appear parent-before-child. General cyclic or multi-parent graphs have first-discovery order, not a topological-order guarantee.

## Queries and caching

```swift
let children = Query(.related(ChildOf.self, to: parent.id))
let anyParent = Query(.related(ChildOf.self))
let subtree = Query(.descendant(of: parent.id))
let graph = Query(.descendant(of: root.id, via: Likes.self))
let healthyChildren = children.with(Health.self)
let roots = Query(!QueryPredicate.related(ChildOf.self))
```

Ordinary, lazy, fast, and typed queries support these predicates and their boolean combinations. Query targets are world-local entity IDs. Descendant predicates exclude the root.

Registered queries cache candidate archetypes, not relationship matches. Relationship terms remain unresolved during archetype filtering, including under negation. Iteration checks live links per entity.

New archetypes invalidate the existing candidate cache. Relationship changes require no archetype-cache invalidation because entity checks read current graph state.

Descendant predicates currently search from each candidate entity. They do not cache transitive results. Large relationship-query workloads need separate measurements.

Query iteration keeps its existing archetype snapshot and lifetime restrictions. Relationship-filtered lazy sequences read live membership. Mutation during iteration does not provide snapshot semantics.

## Deletion and cloning

`entity.destroy()` removes incoming and outgoing links of every relationship type. Direct children survive as roots, and their descendants retain their parents.

`entity.destroyRecursively()` removes the entity and its ChildOf descendants. `destroyRecursively(following:)` applies the same operation to another relationship type. Both return the number of deleted entities.

Recursive deletion captures reachable IDs before removal, visits each entity once, and batches storage invalidation. Links from surviving entities to deleted targets are removed too.

Cloning copies outgoing links with their original targets. It does not clone descendants or incoming links. A self-link on the original therefore targets the original from the clone.

## Demo use

Midnight Survivors links projectiles to their shooter through an exclusive `FiredBy` relationship. The HUD counts active player shots with a relationship query.

Shooter deletion removes the link but leaves shots alive. Each shot retains its hostile/friendly state independently, so orphaned enemy shots remain dangerous. Projectile expiry removes the reverse link automatically.

## Observation and boundaries

Relationship reads participate in world-wide Swift Observation, including empty results. Successful link mutations and deletion notify storage observation. System updates and recursive deletion batch notifications.

Component-event observers still describe component values only. There is no separate relationship-event API.

World retains its single-owner threading model. This implementation adds no inherited component lookup, relationship payloads, or scheduler changes. Those require separate designs.

# Relationships

Link entities, build hierarchies, and query by relationship.

## Link entities

Relationships have no payload. They allow multiple targets and cycles unless their type restricts them.

```swift
enum Likes: Relationship {}

enum EquippedBy: Relationship {
    static var isExclusive: Bool { true }
    static var isAcyclic: Bool { true }
}

let friend = world.createEntity()
let weapon = world.createEntity()

try player.addRelationship(Likes.self, to: friend)
try weapon.addRelationship(EquippedBy.self, to: player)

let liked = player.targets(of: Likes.self)
let admirers = friend.sources(of: Likes.self)
let linked = player.hasRelationship(Likes.self, to: friend)
let equipmentOwners = weapon.ancestors(via: EquippedBy.self)
let equipment = player.descendants(via: EquippedBy.self)

try player.removeRelationship(Likes.self, to: friend)
```

Exclusive relationships replace the previous target. Acyclic relationships reject cycles before replacement, so rejection preserves the existing link.
Relationship policies must remain stable. Writes reject dead entities and cross-world links with `RelationshipError`.
Duplicate additions and absent removals do not invalidate storage. Links occupy separate storage and do not move entities between archetypes or appear in component enumeration.

## Hierarchies and deletion

`ChildOf` allows one parent and rejects cycles. Traversal is breadth-first in link insertion order, excludes the starting entity, and visits each entity once.
General cyclic or multi-parent traversal follows first-discovery order, not a topological ordering.

```swift
let parent = world.createEntity()
let child = world.createEntity()
let grandchild = world.createEntity()

try child.setParent(parent)
try grandchild.setParent(child)

let currentParent = child.parent
let children = parent.children
let ancestors = grandchild.ancestors()
let descendants = parent.descendants()

try child.setParent(nil)               // Detach
try child.setParent(parent)            // Reparent

try world.destroy(parent)                 // Children survive as roots
try world.destroyRecursively(child)       // Delete child and grandchild
try world.destroyRecursively(player, following: EquippedBy.self)
```

Deletion removes all incoming and outgoing links. Cloning copies outgoing links with their original targets, but does not clone descendants or incoming links.
A cloned self-link still targets the original entity. Recursive deletion captures reachable IDs before removal and batches storage invalidation.

Lifecycle methods throw `WorldError.foreignEntity` for a handle from another world. For stale handles, `destroy` returns `false`, `clone` returns `nil`, and recursive deletion returns `0`. Neither case mutates storage.

The library does not give inherited components. The application finds an inherited value itself. To find one, walk `ancestors(via:)` (nearest first) and use the first entity that holds the component. The application decides the order of precedence and what to do when an entity has more than one parent.

Components are not inherited automatically. `query` and `snapshot` match only entities that hold the component. Writes and removals change only the given entity. Observation reports changes for each entity separately. A library inheritance model must resolve the choice between many parents. It must also define how overrides, writes, and removals work. Queries, observation, and parallel access must all support it. For these reasons, inheritance is not part of the relationship API.

## Query relationships

```swift
let owner = world.createEntity()
let projectile = world.createEntity(Position(x: 0, y: 0))
try projectile.setParent(owner)

let directChildren = Query(.related(ChildOf.self, to: owner.id))
let hasParent = Query(.related(ChildOf.self))
let roots = Query(!QueryPredicate.related(ChildOf.self))
let subtree = Query(.descendant(of: owner.id))
let equipped = Query(.descendant(of: owner.id, via: EquippedBy.self))

for row in world.query(Position.self, matching: directChildren) {
    let position = row.values
}
```

Relationship predicates work with every query API. Lazy queries check current links during iteration. Descendant queries exclude their root and do not imply traversal order.


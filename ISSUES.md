# ISSUES.md

---

## 1: Component mutations do not directly invalidate SwiftUI views

+++
status: new
priority: medium
kind: none
created: 2026-09-23T17:28:58Z
+++

World is observable, but component storage mutations do not notify views that read component values. In Demos/Starfall, GameSession maintains a separate frame counter so StarfieldView redraws after simulation updates and player input. Consumers cannot observe component reads directly and must arrange invalidation separately; simulationTime alone does not cover mutations between updates.

---

## 2: System execution order does not preserve registration order

+++
status: new
priority: medium
kind: none
created: 2026-09-23T17:28:58Z
+++

Independent systems do not execute in registration order. World rebuilds its execution order from dictionary keys, so registering spawn, movement, and collision in that sequence does not establish that sequence at runtime. The Starfall demo must declare explicit dependencies for each stage. This is surprising for small sequential simulations, where registration order might otherwise be assumed to determine execution.

---

## 3: Component queries require repeated optional component lookups

+++
status: new
priority: medium
kind: none
created: 2026-09-23T17:28:58Z
+++

World.query(with:) filters entities by component presence but returns untyped Entity handles. Systems must then retrieve each requested component through an optional subscript and repeat presence checks. Starfall MovementSystem and CollisionSystem demonstrate this repeated query-and-guard pattern. The query result cannot express typed access to the components it matched.

---

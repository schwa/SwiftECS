import SwiftECS
import Testing

// Documents the recommended pattern for issue #43: inherited component lookup is
// explicit application traversal over the existing relationship API, not a
// library semantic. The app chooses precedence and multi-parent tie-breaking.

private struct Style: Component, Equatable {
    var color: Int
}

// Nearest-local-wins resolution: self, then ancestors most-specific-first.
private func resolvedStyle(for entity: Entity) -> Style? {
    for candidate in [entity] + entity.ancestors(via: ChildOf.self) {
        if let style = candidate.get(Style.self)?.values {
            return style
        }
    }
    return nil
}

@Test func `explicit ancestor traversal resolves an inherited value`() throws {
    let world = World()
    let grandparent = world.createEntity(Style(color: 1))
    let parent = world.createEntity()
    let child = world.createEntity()
    try parent.setParent(grandparent)
    try child.setParent(parent)

    // Neither parent nor child has a Style; it resolves from the grandparent.
    #expect(resolvedStyle(for: child) == Style(color: 1))
}

@Test func `a nearer ancestor overrides a farther one`() throws {
    let world = World()
    let grandparent = world.createEntity(Style(color: 1))
    let parent = world.createEntity(Style(color: 2))
    let child = world.createEntity()
    try parent.setParent(grandparent)
    try child.setParent(parent)

    #expect(resolvedStyle(for: child) == Style(color: 2))
}

@Test func `a local value takes precedence over inherited values`() throws {
    let world = World()
    let parent = world.createEntity(Style(color: 2))
    let child = world.createEntity(Style(color: 3))
    try child.setParent(parent)

    #expect(resolvedStyle(for: child) == Style(color: 3))
    // Inheritance is read-only sugar: the parent is untouched and queries still
    // match only entities that hold Style locally.
    #expect(world.snapshot(with: Style.self).count == 2)
}

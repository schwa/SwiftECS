import SwiftECS
import Testing

private struct SnippetPosition: Component { var x, y: Double }
private struct SnippetVelocity: Component { var x, y: Double }

@Test func `readme quick start runs`() throws {
    let world = World()
    let entity = world.createEntity(SnippetPosition(x: 0, y: 0), SnippetVelocity(x: 1, y: 0))

    try world.addSystem(System("movement")
        .query(Write<SnippetPosition>(), Read<SnippetVelocity>())
        .each { context, position, velocity in
            position.value.x += velocity.x * context.deltaTime
        })
    try world.update(deltaTime: 1.0 / 60)
    #expect(entity[SnippetPosition.self]?.x == 1.0 / 60)
}

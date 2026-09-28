import SwiftECS

func collisionSystem() -> System {
    let players = SystemQuery(Write<Player>(), Read<Position>())
    let objects = SystemQuery(Read<FallingObject>(), Read<Position>())
    return System("collision").run(players, objects, Commands()) { _, players, objects, commands in
        guard let player = players.first(where: { _ in true }) else {
            return
        }
        let (stateReference, catcher) = player.fields
        var state = stateReference.value
        for row in objects {
            guard state.lives > 0 else {
                continue
            }
            let (object, position) = row.fields
            let caught = abs(position.x - catcher.x) < 0.095 && abs(position.y - catcher.y) < 0.045
            if caught {
                switch object.kind {
                case .star: state.score += 10
                case .meteor: state.lives -= 1
                }
                commands.destroy(row.entityID)
            } else if position.y > 1.05 {
                if object.kind == .star {
                    state.lives -= 1
                }
                commands.destroy(row.entityID)
            }
        }
        stateReference.value = state
    }
}

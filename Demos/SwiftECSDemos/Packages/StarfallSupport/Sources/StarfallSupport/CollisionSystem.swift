import ECS

struct CollisionSystem: System {
    func update(world: World, deltaTime _: Double) {
        do {
            try resolveCollisions(world: world)
        } catch {
            preconditionFailure("Collision entities must belong to their simulation world: \(error)")
        }
    }

    private func resolveCollisions(world: World) throws {
        guard let player = world.snapshot(with: Player.self).first,
              var state = player[Player.self], let catcher = player[Position.self] else {
            return
        }
        for entity in world.snapshot(with: FallingObject.self, Position.self) {
            guard state.lives > 0, let object = entity[FallingObject.self], let position = entity[Position.self] else {
                continue
            }
            let caught = abs(position.x - catcher.x) < 0.095 && abs(position.y - catcher.y) < 0.045
            if caught {
                switch object.kind {
                case .star: state.score += 10
                case .meteor: state.lives -= 1
                }
                try world.destroy(entity)
            } else if position.y > 1.05 {
                if object.kind == .star {
                    state.lives -= 1
                }
                try world.destroy(entity)
            }
        }
        player.set(state)
    }
}

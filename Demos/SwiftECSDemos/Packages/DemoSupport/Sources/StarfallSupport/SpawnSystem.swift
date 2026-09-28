import SwiftECS

final class SpawnSystem {
    private var remaining = 0.3
    private var count = 0

    var system: System {
        System("spawn").run(Commands()) { [self] context, commands in
            remaining -= context.deltaTime
            guard remaining <= 0 else {
                return
            }
            count += 1
            let difficulty = min(context.simulationTime / 60, 1)
            remaining += 0.8 - difficulty * 0.4
            try commands.create(
                Position(x: Double.random(in: 0.08...0.92), y: -0.04),
                Velocity(y: 0.22 + difficulty * 0.22),
                FallingObject(kind: count.isMultiple(of: 4) ? .meteor : .star)
            )
        }
    }
}

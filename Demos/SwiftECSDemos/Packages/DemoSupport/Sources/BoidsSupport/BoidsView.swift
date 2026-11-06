import SwiftECS
import SwiftUI

public struct BoidsView: View {
    @State private var boidCount = BoidsSettings.boidCount
    @State private var session = BoidsSession(count: BoidsSettings.boidCount)

    public init() {}

    public var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Picker("Boids", selection: $boidCount) {
                    ForEach(BoidsSettings.boidCountChoices, id: \.self) { count in
                        Text(count, format: .number).tag(count)
                    }
                }
                .fixedSize()
                Text("\(session.parallelism) workers")
                Text("\(session.updateMilliseconds, format: .number.precision(.fractionLength(1))) ms per update")
                    .monospacedDigit()
                #if DEBUG
                Text("Debug build").foregroundStyle(.red)
                #endif
                if let failure = session.failure {
                    Text(failure).foregroundStyle(.red)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Canvas { context, size in
                let scale = size.width / BoidsSettings.bounds.x
                context.scaleBy(x: scale, y: scale)
                context.fill(path(), with: .color(.mint))
            }
            .aspectRatio(BoidsSettings.bounds.x / BoidsSettings.bounds.y, contentMode: .fit)
            .background(Color(red: 0.02, green: 0.03, blue: 0.06))
            .clipShape(.rect(cornerRadius: 16))
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.025, green: 0.035, blue: 0.07))
        .preferredColorScheme(.dark)
        // Restarts with a new flock when the count changes. The canvas redraws when `session.boids` changes.
        .task(id: boidCount) {
            if session.boids.count != boidCount {
                session = BoidsSession(count: boidCount)
            }
            while !Task.isCancelled {
                await session.tick(at: .now)
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
    }

    // One path for the whole flock. Filling thousands of separate shapes is much slower.
    private func path() -> Path {
        var path = Path()
        for boid in session.boids {
            let speed = max((boid.velocity * boid.velocity).sum().squareRoot(), 1e-9)
            let forward = boid.velocity / speed * 4
            let side = SIMD2(-forward.y, forward.x) * 0.5
            let tip = boid.position + forward
            let left = boid.position - forward + side
            let right = boid.position - forward - side
            path.move(to: CGPoint(x: tip.x, y: tip.y))
            path.addLine(to: CGPoint(x: left.x, y: left.y))
            path.addLine(to: CGPoint(x: right.x, y: right.y))
            path.closeSubpath()
        }
        return path
    }
}

#Preview {
    BoidsView().frame(width: 900, height: 650)
}

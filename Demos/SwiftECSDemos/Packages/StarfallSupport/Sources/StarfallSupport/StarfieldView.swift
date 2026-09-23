import ECS
import SwiftUI

struct StarfieldView: View {
    let game: GameSession

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !game.running || game.paused)) { timeline in
            GeometryReader { geometry in
                Canvas { context, size in
                    for index in 0..<90 {
                        let horizontalSeed: Int = (index * 137 + 31) % 997
                        let verticalSeed: Int = (index * 251 + 17) % 991
                        let x = Double(horizontalSeed) / 997.0 * size.width
                        let y = Double(verticalSeed) / 991.0 * size.height
                        let radius = index.isMultiple(of: 5) ? 1.5 : 0.8
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)), with: .color(.white.opacity(0.35)))
                    }
                    for entity in game.world.query(with: Position.self) {
                        guard let position = entity[Position.self] else {
                            continue
                        }
                        let point = CGPoint(x: position.x * size.width, y: position.y * size.height)
                        if entity.contains(Player.self) {
                            let width = size.width * 0.15
                            let rect = CGRect(x: point.x - width / 2, y: point.y - 7, width: width, height: 14)
                            context.fill(Path(roundedRect: rect, cornerRadius: 7), with: .color(.cyan))
                            context.fill(Path(ellipseIn: CGRect(x: point.x - 5, y: point.y + 10, width: 10, height: 16)), with: .color(.cyan.opacity(0.4)))
                        } else if let object = entity[FallingObject.self] {
                            let isStar = object.kind == .star
                            // Canvas exposes accessibility on the playfield, not on drawing primitives.
                            // swiftlint:disable:next accessibility_label_for_image
                            let image = Image(systemName: isStar ? "star.fill" : "flame.fill")
                            var resolved = context.resolve(image)
                            resolved.shading = .color(isStar ? .yellow : .red)
                            let side = min(size.width, size.height) * 0.055
                            context.draw(resolved, in: CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side))
                        }
                    }
                }
                .background(.indigo.opacity(0.12))
                .clipShape(.rect(cornerRadius: 20))
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    game.move(to: value.location.x / max(geometry.size.width, 1))
                })
                .accessibilityLabel("Starfield")
                .accessibilityHint("Drag to steer the catcher, or use the move buttons below.")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: game.nudge(0.08)
                    case .decrement: game.nudge(-0.08)
                    @unknown default: break
                    }
                }
            }
            .onChange(of: timeline.date) { _, date in
                game.tick(at: date)
            }
        }
    }
}

#Preview {
    StarfieldView(game: GameSession())
        .frame(width: 400, height: 500)
}

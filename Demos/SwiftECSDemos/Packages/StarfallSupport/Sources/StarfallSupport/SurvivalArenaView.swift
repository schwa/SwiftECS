import ECS
import SwiftUI

struct SurvivalArenaView: View {
    let game: SurvivalSession
    @FocusState private var focused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !game.started || game.paused || game.hero.finished || game.hero.needsUpgrade)) { timeline in
            GeometryReader { geometry in
                Canvas { context, size in
                    let scale = size.width / SurvivalSystem.arena.x
                    context.scaleBy(x: scale, y: scale)
                    drawGround(context: &context)
                    for row in game.world.query(SurvivalComponents.Body.self, SurvivalComponents.Sprite.self) {
                        let (body, sprite) = row.values
                        let point = CGPoint(x: body.position.x, y: body.position.y)
                        let glyph = context.resolve(Text(sprite.emoji).font(.system(size: sprite.emoji == "💎" ? 18 : body.radius * 2)))
                        context.draw(glyph, at: point)
                    }
                    if game.hero.invulnerability > 0, let player = game.world.snapshot(with: SurvivalComponents.Hero.self).first,
                       let body = player[SurvivalComponents.Body.self] {
                        let ring = CGRect(x: body.position.x - 25, y: body.position.y - 25, width: 50, height: 50)
                        context.stroke(Path(ellipseIn: ring), with: .color(.cyan.opacity(0.8)), lineWidth: 3)
                    }
                }
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            focused = true
                            let scale = SurvivalSystem.arena.x / max(geometry.size.width, 1)
                            game.steer(to: SIMD2(value.location.x * scale, value.location.y * scale))
                        }
                        .onEnded { _ in game.releasePointer() }
                )
            }
            .onChange(of: timeline.date) { _, date in game.tick(at: date) }
        }
        .aspectRatio(SurvivalSystem.arena.x / SurvivalSystem.arena.y, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.15)) }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: [.down, .repeat, .up]) { press in
            let key: String
            switch press.key {
            case .leftArrow: key = "a"
            case .rightArrow: key = "d"
            case .upArrow: key = "w"
            case .downArrow: key = "s"
            default: key = press.characters.lowercased()
            }
            guard ["w", "a", "s", "d"].contains(key) else {
                return .ignored
            }
            game.setKey(key, pressed: press.phase != .up)
            return .handled
        }
        .onChange(of: game.started) { focused = true }
        .onChange(of: game.paused) { focused = !game.paused }
        .onChange(of: game.hero.needsUpgrade) { focused = !game.hero.needsUpgrade }
        .accessibilityLabel("Survival arena")
        .accessibilityHint("Hold and drag to move, or use W A S D or arrow keys. Attacks fire automatically.")
    }

    private func drawGround(context: inout GraphicsContext) {
        let arena = CGRect(x: 0, y: 0, width: SurvivalSystem.arena.x, height: SurvivalSystem.arena.y)
        context.fill(Path(arena), with: .color(Color(red: 0.055, green: 0.105, blue: 0.085)))
        var grid = Path()
        for x in stride(from: 0.0, through: SurvivalSystem.arena.x, by: 50) {
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: SurvivalSystem.arena.y))
        }
        for y in stride(from: 0.0, through: SurvivalSystem.arena.y, by: 50) {
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: SurvivalSystem.arena.x, y: y))
        }
        context.stroke(grid, with: .color(.white.opacity(0.035)), lineWidth: 1)
        let grave = context.resolve(Text("🪦").font(.title))
        for point in [CGPoint(x: 60, y: 60), CGPoint(x: 940, y: 60), CGPoint(x: 60, y: 640), CGPoint(x: 940, y: 640)] {
            context.draw(grave, at: point)
        }
    }
}

#Preview {
    SurvivalArenaView(game: SurvivalSession())
        .frame(width: 800)
}

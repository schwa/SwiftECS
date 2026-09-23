import SwiftUI

public struct SurvivalView: View {
    @State private var game = SurvivalSession()
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        VStack {
            SurvivalHUDView(hero: game.hero, visibleEntityCount: game.visibleEntityCount, totalEntityCount: game.world.entityCount, playerShotCount: game.activePlayerShotCount)
            SurvivalArenaView(game: game)
                .overlay {
                    if game.hero.needsUpgrade, !game.hero.finished {
                        SurvivalUpgradeView(game: game)
                    } else if !game.started || game.paused || game.hero.finished {
                        SurvivalMenuView(game: game)
                    }
                }
            HStack {
                Text("WASD / arrows · Hold and drag to move · Auto-fire")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(game.paused ? "Resume" : "Pause", systemImage: game.paused ? "play.fill" : "pause.fill") {
                    game.setPaused(!game.paused)
                }
                .disabled(!game.started || game.hero.finished || game.hero.needsUpgrade)
                .keyboardShortcut(.space, modifiers: [])
            }
        }
        .padding()
        .frame(maxWidth: 1_200)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.025, green: 0.045, blue: 0.04))
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                game.setPaused(true)
            }
        }
        .onDisappear { game.setPaused(true) }
    }
}

#Preview {
    SurvivalView().frame(width: 900, height: 750)
}

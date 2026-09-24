import SwiftUI

struct SurvivalMenuView: View {
    let game: SurvivalSession

    var body: some View {
        VStack {
            Text(game.hero.finished ? (game.hero.health > 0 ? "🌅" : "💀") : "🧙✨🧟")
                .font(.largeTitle)
            Text(game.hero.finished ? (game.hero.health > 0 ? "You survived the night!" : "The horde got you") : game.started ? "Paused" : "Survive until dawn")
                .font(.title.bold())
            if game.hero.finished {
                Text("Level \(game.hero.level) · \(game.hero.kills) enemies defeated")
            } else {
                Text("Survive for 90 seconds. Your wand fires automatically.\nCollect 💎 to level up. Dodge 😈 and their 🔥.")
                    .multilineTextAlignment(.center)
                Text("Move with WASD, arrows, or hold and drag.")
                    .foregroundStyle(.secondary)
            }
            if let failure = game.failure {
                Text(failure).foregroundStyle(.red)
            }
            Button(game.started && !game.hero.finished ? "Resume" : game.hero.finished ? "Try again" : "Enter the graveyard") {
                if game.started, !game.hero.finished {
                    game.setPaused(false)
                } else {
                    game.start()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.mint)
            if game.started, !game.hero.finished {
                Button("Restart run") { game.start() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .padding()
    }
}

#Preview {
    SurvivalMenuView(game: SurvivalSession())
}

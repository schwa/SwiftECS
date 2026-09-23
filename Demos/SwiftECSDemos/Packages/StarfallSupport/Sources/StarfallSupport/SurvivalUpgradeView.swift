import SwiftUI

struct SurvivalUpgradeView: View {
    let game: SurvivalSession

    var body: some View {
        VStack {
            Text("✨ Level \(game.hero.level)").font(.largeTitle.bold())
            Text("Choose a power. The horde can wait.")
                .foregroundStyle(.secondary)
            Button { game.choose(.magic) } label: {
                VStack {
                    Text("🪄 Stronger magic").font(.headline)
                    Text("+1 damage per shot").font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }
            Button { game.choose(.haste) } label: {
                VStack {
                    Text("⚡ Quick feet, quick spells").font(.headline)
                    Text("Faster spells and movement").font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }
            Button { game.choose(.vitality) } label: {
                VStack {
                    Text("❤️ Second wind").font(.headline)
                    Text("+1 maximum health and a full heal").font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }
        }
        .buttonStyle(.bordered)
        .tint(.mint)
        .padding()
        .frame(maxWidth: 400)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .padding()
    }
}

#Preview {
    SurvivalUpgradeView(game: SurvivalSession())
}

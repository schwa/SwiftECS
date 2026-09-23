import SwiftUI

struct SurvivalHUDView: View {
    let hero: SurvivalComponents.Hero
    let visibleEntityCount: Int
    let totalEntityCount: Int

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Midnight Survivors").font(.title.bold())
                Spacer()
                Text("⏱ \(max(0, 90 - Int(hero.elapsed)))s")
                    .accessibilityLabel("\(max(0, 90 - Int(hero.elapsed))) seconds remaining")
                Text("💀 \(hero.kills)")
                    .accessibilityLabel("\(hero.kills) enemies defeated")
                Text("❤️ \(hero.health)/\(hero.maximumHealth)")
                    .accessibilityLabel("Health \(hero.health) of \(hero.maximumHealth)")
            }
            HStack {
                Text("Level \(hero.level)").font(.headline)
                Text("Entities: \(visibleEntityCount)/\(totalEntityCount)")
                    .font(.caption)
                    .accessibilityLabel("\(visibleEntityCount) entities in arena, \(totalEntityCount) total")
                ProgressView(value: Double(hero.experience), total: Double(hero.experienceNeeded))
                    .tint(.mint)
                    .accessibilityLabel("Experience")
                Text("💎 \(hero.experience)/\(hero.experienceNeeded)").font(.caption)
            }
        }
        .monospacedDigit()
    }
}

#Preview {
    SurvivalHUDView(hero: SurvivalComponents.Hero(), visibleEntityCount: 42, totalEntityCount: 50).padding()
}

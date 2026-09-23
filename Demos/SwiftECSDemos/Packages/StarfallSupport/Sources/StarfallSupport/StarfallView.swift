import SwiftUI

public struct StarfallView: View {
    @State private var game = GameSession()
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        VStack {
            HStack {
                Text("Starfall").font(.largeTitle.bold())
                Spacer()
                Label("\(game.score)", systemImage: "star.fill")
                    .foregroundStyle(.yellow)
                Label("\(game.lives)", systemImage: "heart.fill")
                    .foregroundStyle(.pink)
            }
            .monospacedDigit()
            StarfieldView(game: game)
                .overlay {
                    if !game.running || game.paused {
                        VStack {
                            Text(game.lives == 0 ? "Flight complete" : game.paused ? "Paused" : "Catch a little starlight")
                                .font(.title.bold())
                            Text("Catch gold stars. Dodge red meteors.\nMiss a star or hit a meteor and lose a heart.")
                                .multilineTextAlignment(.center)
                            if let failure = game.failure {
                                Text(failure).foregroundStyle(.red)
                            }
                            Button(game.paused ? "Resume" : game.lives == 0 ? "Play again" : "Launch") {
                                if game.paused {
                                    game.setPaused(false)
                                } else {
                                    game.start()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                        .padding()
                        .background(.regularMaterial, in: .rect(cornerRadius: 20))
                        .padding()
                    }
                }
            HStack {
                Button("Move left", systemImage: "arrow.left") { game.nudge(-0.08) }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Text("Drag to steer · Arrow keys to move")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Move right", systemImage: "arrow.right") { game.nudge(0.08) }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Spacer()
                Button(game.paused ? "Resume" : "Pause", systemImage: game.paused ? "play.fill" : "pause.fill") {
                    game.setPaused(!game.paused)
                }
                .disabled(!game.running)
                .keyboardShortcut(.space, modifiers: [])
            }
        }
        .padding()
        .background(Color(red: 0.035, green: 0.045, blue: 0.11))
        .preferredColorScheme(.dark)
        .onDisappear { game.setPaused(true) }
        .onChange(of: scenePhase) {
            if scenePhase != .active, game.running {
                game.setPaused(true)
            }
        }
    }
}

#Preview {
    StarfallView()
        .frame(width: 600, height: 700)
}

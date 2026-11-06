import SurvivalSupport
import SwiftUI

struct DemoPickerView: View {
    private enum Demo: Hashable {
        case survivors
    }

    var body: some View {
        NavigationStack {
            VStack {
                Text("ECS Arcade").font(.largeTitle.bold())
                Text("Pick a game").foregroundStyle(.secondary)
                NavigationLink(value: Demo.survivors) {
                    VStack {
                        Text("🧙✨🧟").font(.largeTitle)
                        Text("Midnight Survivors").font(.title2.bold())
                        Text("Auto-fire, gather gems, and outlast the horde.")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
            .buttonStyle(.bordered)
            .tint(.mint)
            .padding()
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.025, green: 0.035, blue: 0.07))
            .navigationDestination(for: Demo.self) { demo in
                switch demo {
                case .survivors:
                    SurvivalView()
                        .navigationTitle("Midnight Survivors")
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    DemoPickerView().frame(width: 900, height: 750)
}

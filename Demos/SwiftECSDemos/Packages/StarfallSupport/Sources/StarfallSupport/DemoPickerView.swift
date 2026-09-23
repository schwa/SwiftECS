import SwiftUI

public struct DemoPickerView: View {
    private enum Demo: Hashable {
        case starfall, survivors
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack {
                Text("ECS Arcade").font(.largeTitle.bold())
                Text("Pick a game").foregroundStyle(.secondary)
                NavigationLink(value: Demo.starfall) {
                    VStack {
                        Text("🌠").font(.largeTitle)
                        Text("Starfall").font(.title2.bold())
                        Text("Catch stars. Dodge meteors.")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
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
                case .starfall:
                    StarfallView()
                        .navigationTitle("Starfall")
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

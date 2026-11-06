enum BoidsSettings {
    static let bounds = SIMD2<Double>(1_600, 1_000)
    static let boidCount = 1_000
    static let boidCountChoices = [1_000, 5_000, 10_000, 20_000, 50_000, 100_000]
    static let neighborRadius = 24.0
    static let separationRadius = 8.0
    static let minimumSpeed = 40.0
    static let maximumSpeed = 90.0
    static let alignmentWeight = 1.5
    static let cohesionWeight = 0.8
    static let separationWeight = 60.0
}

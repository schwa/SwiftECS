import SwiftECS

struct Boid: ConcurrentComponent {
    var position: SIMD2<Double>
    var velocity: SIMD2<Double>
}

import Foundation
@testable import SwiftECS
import Testing

private final class RefHolder {
    var transform: ComponentRef<Transform>
    init(_ transform: ComponentRef<Transform>) { self.transform = transform }
    @inline(never) func read() -> Double { transform.value.x }
    @inline(never) func readUntracked() -> Double { transform.untrackedValue.x }
}

// Opt-in: ECS_RUN_REF_BENCHMARKS=1 xcb test -c release -- --filter componentRefReadBenchmark
// Results go to /tmp/SwiftECS-componentRef-benchmark.txt.
@Test(.enabled(if: ProcessInfo.processInfo.environment["ECS_RUN_REF_BENCHMARKS"] != nil))
func componentRefReadBenchmark() throws {
    let world = World()
    let count = 100_000
    let rounds = 20
    var refs: [ComponentRef<Transform>] = []
    refs.reserveCapacity(count)
    for index in 0..<count {
        let entity = world.createEntity(Transform(x: Double(index), y: 0, z: 0))
        refs.append(try #require(world.componentRef(Transform.self, for: entity.id)))
    }
    var lines: [String] = []
    func report(_ name: String, _ start: ContinuousClock.Instant, _ sum: Double) {
        let elapsed = start.duration(to: .now)
        let nanoseconds = Double(elapsed.components.seconds) * 1e9 + Double(elapsed.components.attoseconds) / 1e9
        lines.append("\(name): \(String(format: "%.2f", nanoseconds / Double(count * rounds))) ns (checksum \(sum))")
    }
    var sum = 0.0
    var start = ContinuousClock.now
    for _ in 0..<rounds {
        for ref in refs {
            sum += ref.value.x
        }
    }
    report("value read", start, sum)
    sum = 0
    start = .now
    for _ in 0..<rounds {
        for ref in refs {
            sum += ref.untrackedValue.x
        }
    }
    report("untrackedValue read", start, sum)
    start = .now
    for _ in 0..<rounds {
        for ref in refs {
            ref.value.x += 1
        }
    }
    report("value write", start, 0)
    // SceneSprockets keeps one ref per node field in a node object.
    let nodes = refs.map(RefHolder.init)
    sum = 0
    start = .now
    for _ in 0..<rounds {
        for node in nodes {
            sum += node.read()
        }
    }
    report("holder value read", start, sum)
    sum = 0
    start = .now
    for _ in 0..<rounds {
        for node in nodes {
            sum += node.readUntracked()
        }
    }
    report("holder untrackedValue read", start, sum)
    try lines.joined(separator: "\n").write(toFile: "/tmp/SwiftECS-componentRef-benchmark.txt", atomically: true, encoding: .utf8)
}

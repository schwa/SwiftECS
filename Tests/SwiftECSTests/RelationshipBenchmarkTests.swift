import Foundation
@testable import SwiftECS
import Testing

// Non-acyclic, multi-target link for DAG measurements.
private enum BenchLink: Relationship {}

// Opt-in relationship scaling measurements for issue #19. Entity creation is
// kept outside the timer; result counts are verified outside timing. It covers
// deep/broad/DAG construction, reparenting, direct and descendant queries
// (registered and unregistered), transitive traversal, and recursive deletion.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ECS_RUN_RELATIONSHIP_BENCHMARKS"] == "1"), .serialized)
struct RelationshipBenchmarkTests {
    @MainActor @Test func measureRelationships() throws {
        let environment = ProcessInfo.processInfo.environment
        let rounds = environment["ECS_REL_ROUNDS"].flatMap(Int.init) ?? 3
        let deepDepth = environment["ECS_REL_DEEP"].flatMap(Int.init) ?? 3_000
        let broadWidth = environment["ECS_REL_BROAD"].flatMap(Int.init) ?? 50_000
        let queryRepeats = environment["ECS_REL_QUERY_REPEATS"].flatMap(Int.init) ?? 20
        precondition(rounds > 0 && deepDepth > 1 && broadWidth > 0 && queryRepeats > 0)

        output("relationship OS=\(ProcessInfo.processInfo.operatingSystemVersionString) processors=\(ProcessInfo.processInfo.activeProcessorCount)")
        #if DEBUG
        output("relationship configuration=debug (measure in Release)")
        #else
        output("relationship configuration=release")
        #endif
        output("relationship rounds=\(rounds)")

        try deepChain(depth: deepDepth, rounds: rounds)
        try broadStar(width: broadWidth, rounds: rounds)
        try layeredDAG(layers: 6, width: 2_000, fanIn: 3, rounds: rounds)
        try reparenting(count: 20_000, iterations: 5, rounds: rounds)
        try directQueries(width: broadWidth, repeats: queryRepeats, rounds: rounds)
        try descendantWork(branching: 10, depth: 5, repeats: queryRepeats, rounds: rounds)
        try recursiveDeletion(branching: 10, depth: 5, rounds: rounds)
    }

    // Acyclic chain: each insert runs a cycle check that walks toward the root.
    @MainActor private func deepChain(depth: Int, rounds: Int) throws {
        var samples: [Double] = []
        for _ in 0..<rounds {
            let world = World()
            let nodes = (0..<depth).map { _ in world.createEntity() }
            let start = ContinuousClock.now
            for index in 1..<depth {
                try nodes[index].setParent(nodes[index - 1])
            }
            samples.append(milliseconds(start.duration(to: .now)))
            #expect(nodes[depth - 1].ancestors().count == depth - 1)
        }
        report("deep-chain depth=\(depth)", samples)
    }

    // Broad star: root with many direct children; cheap acyclic checks.
    @MainActor private func broadStar(width: Int, rounds: Int) throws {
        var samples: [Double] = []
        for _ in 0..<rounds {
            let world = World()
            let root = world.createEntity()
            let children = (0..<width).map { _ in world.createEntity() }
            let start = ContinuousClock.now
            for child in children {
                try child.setParent(root)
            }
            samples.append(milliseconds(start.duration(to: .now)))
            #expect(root.children.count == width)
        }
        report("broad-star width=\(width)", samples)
    }

    // Layered DAG with multiple parents per node (non-acyclic link).
    @MainActor private func layeredDAG(layers: Int, width: Int, fanIn: Int, rounds: Int) throws {
        var samples: [Double] = []
        var edges = 0
        for _ in 0..<rounds {
            let world = World()
            let grid = (0..<layers).map { _ in (0..<width).map { _ in world.createEntity() } }
            let start = ContinuousClock.now
            var linked = 0
            for layer in 1..<layers {
                for (index, node) in grid[layer].enumerated() {
                    for offset in 0..<fanIn {
                        let parent = grid[layer - 1][(index + offset) % width]
                        try node.addRelationship(BenchLink.self, to: parent)
                        linked += 1
                    }
                }
            }
            samples.append(milliseconds(start.duration(to: .now)))
            edges = linked
            #expect(grid[layers - 1][0].targets(of: BenchLink.self).count == fanIn)
        }
        report("layered-dag layers=\(layers) width=\(width) fanIn=\(fanIn) edges=\(edges)", samples)
    }

    // Frequent reparenting: exclusive ChildOf replaces the previous parent.
    @MainActor private func reparenting(count: Int, iterations: Int, rounds: Int) throws {
        var samples: [Double] = []
        for _ in 0..<rounds {
            let world = World()
            let alpha = world.createEntity()
            let beta = world.createEntity()
            let entities = (0..<count).map { _ in world.createEntity() }
            for entity in entities {
                try entity.setParent(alpha)
            }
            let start = ContinuousClock.now
            for iteration in 0..<iterations {
                let parent = iteration.isMultiple(of: 2) ? beta : alpha
                for entity in entities {
                    try entity.setParent(parent)
                }
            }
            samples.append(milliseconds(start.duration(to: .now)))
            let finalParent = iterations.isMultiple(of: 2) ? alpha : beta
            #expect(entities[0].parent?.id == finalParent.id)
        }
        report("reparent count=\(count) iterations=\(iterations)", samples)
    }

    // Direct child query, registered vs unregistered, on a broad star.
    @MainActor private func directQueries(width: Int, repeats: Int, rounds: Int) throws {
        for registered in [false, true] {
            var samples: [Double] = []
            for _ in 0..<rounds {
                let world = World()
                let root = world.createEntity()
                for _ in 0..<width { try world.createEntity().setParent(root) }
                let query = Query(.related(ChildOf.self, to: root.id))
                if registered {
                    world.register(query)
                }
                var matched = 0
                let start = ContinuousClock.now
                for _ in 0..<repeats {
                    matched = world.snapshot(matching: query).count
                }
                samples.append(milliseconds(start.duration(to: .now)) / Double(repeats))
                #expect(matched == width)
            }
            report("direct-query registered=\(registered) width=\(width)", samples, unit: "ms/query")
        }
    }

    // Descendant predicate and transitive traversal over a balanced tree.
    @MainActor private func descendantWork(branching: Int, depth: Int, repeats: Int, rounds: Int) throws {
        var querySamples: [Double] = []
        var traversalSamples: [Double] = []
        var nodeCount = 0
        for _ in 0..<rounds {
            let world = World()
            let root = world.createEntity()
            let total = buildTree(world: world, root: root, branching: branching, depth: depth)
            nodeCount = total
            let query = Query(.descendant(of: root.id))
            var matched = 0
            let queryStart = ContinuousClock.now
            for _ in 0..<repeats {
                matched = world.snapshot(matching: query).count
            }
            querySamples.append(milliseconds(queryStart.duration(to: .now)) / Double(repeats))
            #expect(matched == total - 1)
            var traversed = 0
            let traversalStart = ContinuousClock.now
            for _ in 0..<repeats {
                traversed = root.descendants().count
            }
            traversalSamples.append(milliseconds(traversalStart.duration(to: .now)) / Double(repeats))
            #expect(traversed == total - 1)
        }
        report("descendant-query nodes=\(nodeCount)", querySamples, unit: "ms/query")
        report("descendant-traversal nodes=\(nodeCount)", traversalSamples, unit: "ms/traversal")
    }

    // Recursive deletion of a balanced tree.
    @MainActor private func recursiveDeletion(branching: Int, depth: Int, rounds: Int) throws {
        var samples: [Double] = []
        var nodeCount = 0
        for _ in 0..<rounds {
            let world = World()
            let root = world.createEntity()
            let total = buildTree(world: world, root: root, branching: branching, depth: depth)
            nodeCount = total
            let start = ContinuousClock.now
            let deleted = try world.destroyRecursively(root)
            samples.append(milliseconds(start.duration(to: .now)))
            #expect(deleted == total)
            #expect(world.entityCount == 0)
        }
        report("recursive-deletion nodes=\(nodeCount)", samples)
    }

    @MainActor private func buildTree(world: World, root: Entity, branching: Int, depth: Int) -> Int {
        var frontier = [root]
        var total = 1
        for _ in 0..<depth {
            var next: [Entity] = []
            next.reserveCapacity(frontier.count * branching)
            for parent in frontier {
                for _ in 0..<branching {
                    let child = world.createEntity()
                    try? child.setParent(parent)
                    next.append(child)
                    total += 1
                }
            }
            frontier = next
        }
        return total
    }

    private func report(_ label: String, _ samples: [Double], unit: String = "ms") {
        let sorted = samples.sorted()
        output("relationship \(label) median=\(format(sorted[sorted.count / 2])) min=\(format(sorted.first!)) max=\(format(sorted.last!)) \(unit)")
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(3)))
    }

    private func output(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}

@testable import SurvivalSupport
import SwiftECS
import Testing

@MainActor @Test func `stateful survival stages retain their serial fallback`() async throws {
    let game = SurvivalSession()
    game.start()
    try await game.world.update(deltaTime: 0.01, parallelism: 4)
    #expect(game.hero.elapsed == 0.01)
    #expect(game.world.lastRunStatistics.systemCount == 8)
    #expect(game.world.lastRunStatistics.parallelTaskCount == 0)
}

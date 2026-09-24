import simd
import SwiftECS

enum SurvivalComponents {
    struct Body: Component {
        var position: SIMD2<Double>
        var radius: Double
    }

    struct Sprite: Component {
        var emoji: String
    }

    struct Hero: Component {
        var health = 5
        var maximumHealth = 5
        var experience = 0
        var level = 1
        var kills = 0
        var elapsed = 0.0
        var damage = 1
        var fireInterval = 0.45
        var speed = 210.0
        var invulnerability = 0.0
        var needsUpgrade = false

        var experienceNeeded: Int { level * 5 }
        var finished: Bool { health <= 0 || elapsed >= 90 }
    }

    struct Enemy: Component {
        var health: Int
        var speed: Double
        var shoots: Bool
        var cooldown: Double
    }

    struct Shot: Component {
        var velocity: SIMD2<Double>
        var damage: Int
        var hostile: Bool
        var lifetime: Double
    }

    struct Gem: Component {}
}

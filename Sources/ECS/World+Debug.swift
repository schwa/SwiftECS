// MARK: - Debug Utilities

extension World {
    /// Statistics about the world.
    public struct Stats: CustomStringConvertible {
        /// Number of entities in the world.
        public let entityCount: Int
        /// Number of archetypes.
        public let archetypeCount: Int
        /// Number of unique component types.
        public let componentTypeCount: Int
        /// Number of systems.
        public let systemCount: Int

        public var description: String {
            """
            World Stats:
              Entities: \(entityCount)
              Archetypes: \(archetypeCount)
              Component Types: \(componentTypeCount)
              Systems: \(systemCount)
            """
        }
    }

    /// Get statistics about the world.
    public var stats: Stats {
        var componentTypes = Set<ComponentType>()
        for archetype in archetypes.values {
            for type in archetype.signature.types {
                componentTypes.insert(type)
            }
        }

        return Stats(
            entityCount: entityCount,
            archetypeCount: archetypes.count,
            componentTypeCount: componentTypes.count,
            systemCount: systemCount
        )
    }

    /// Number of registered systems.
    public var systemCount: Int {
        systems.count
    }

    /// Get all component types for an entity.
    public func componentTypes(for entity: Entity) -> [ComponentType] {
        guard let location = entityLocations[entity.id] else { return [] }
        return Array(location.signature.types)
    }

    /// Print all entities and their components to standard output.
    public func dump() {
        print(dumpString())
    }

    /// Get a string representation of all entities and their components.
    public func dumpString() -> String {
        var lines: [String] = []
        lines.append("World Dump:")
        lines.append("===========")
        lines.append("")

        // Group entities by archetype for cleaner output
        for (signature, archetype) in archetypes.sorted(by: { $0.value.entities.count > $1.value.entities.count }) {
            guard !archetype.entities.isEmpty else { continue }

            let typeNames = signature.types.map(\.name).sorted().joined(separator: ", ")
            lines.append("Archetype [\(typeNames)] (\(archetype.entities.count) entities)")
            lines.append(String(repeating: "-", count: 60))

            for entityID in archetype.entities {
                lines.append("  Entity \(entityID)")
            }
            lines.append("")
        }

        // Summary
        lines.append("Summary:")
        lines.append("  Total Entities: \(entityCount)")
        lines.append("  Total Archetypes: \(archetypes.count)")

        return lines.joined(separator: "\n")
    }

    /// Get a detailed string representation including component values.
    /// Note: Only works for components that conform to CustomStringConvertible.
    public func dumpDetailed() -> String {
        var lines: [String] = []
        lines.append("World Dump (Detailed):")
        lines.append("======================")
        lines.append("")

        for (signature, archetype) in archetypes.sorted(by: { $0.value.entities.count > $1.value.entities.count }) {
            guard !archetype.entities.isEmpty else { continue }

            let typeNames = signature.types.map(\.name).sorted().joined(separator: ", ")
            lines.append("Archetype [\(typeNames)] (\(archetype.entities.count) entities)")
            lines.append(String(repeating: "-", count: 60))

            for entityID in archetype.entities {
                lines.append("  Entity \(entityID)")
                for type in signature.types.sorted(by: { $0.name < $1.name }) {
                    lines.append("    - \(type.name)")
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

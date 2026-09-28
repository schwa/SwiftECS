public struct SystemQueryBuilder<each Term: SystemTerm> {
    @usableFromInline internal let system: System
    @usableFromInline internal let query: SystemQuery<repeat each Term>

    @inlinable
    public func each(_ body: @escaping (SystemContext, repeat (each Term).Output) throws -> Void) -> System {
        system.run(query) { context, rows in
            for row in rows {
                try body(context, repeat each row.fields)
            }
        }
    }

    public func run(_ body: @escaping (SystemContext, SystemRows<repeat each Term>) throws -> Void) -> System {
        system.run(query, body: body)
    }
}

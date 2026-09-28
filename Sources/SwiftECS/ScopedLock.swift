#if canImport(os)
import os
#else
import Foundation
#endif

@usableFromInline
internal final class ScopedLock: Sendable {
    #if canImport(os)
    @usableFromInline let lock = OSAllocatedUnfairLock()
    #else
    @usableFromInline let lock = NSLock()
    #endif

    @inlinable
    @inline(__always)
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        #if canImport(os)
        // Serial callers may hold non-Sendable values; the lock still protects every access.
        try lock.withLockUnchecked(body)
        #else
        try lock.withLock(body)
        #endif
    }
}

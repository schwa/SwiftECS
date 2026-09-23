# Typed query pack investigation (#7)

## Result

Parameter packs can store typed ECS columns and read or write their values without per-access dictionary lookups. Two expression forms still fail.

The probe is not a proposed public API. It uses tuple positions, not component-type subscripts. We did not measure performance.

## Toolchain

Tested on arm64 macOS with the selected Xcode 27.0 installation:

```text
swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)
Target: arm64-apple-macosx27.0.0
```

The installed Xcode 27.1 and 27.2 selections report the same Swift version and reject the direct-access expression too.

Swift 6.2 compatibility remains unverified. The original crash has no retained reproduction, so these results do not prove that its compiler bug is fixed.

## Standalone reproduction

Run from the repository root. The default script must exit successfully:

```sh
xcrun swift Experiments/TypedQueryPacks/Probe.swift
```

The following variants must fail on the tested compiler:

```sh
xcrun swift -D DIRECT_ACCESS Experiments/TypedQueryPacks/Probe.swift
xcrun swift -D SINGLE_ASSIGNMENT Experiments/TypedQueryPacks/Probe.swift
```

Direct array access inside a pack expansion produces:

```text
error: failed to produce diagnostic for expression; please submit a bug report (https://swift.org/contributing/#reporting-bugs)
```

A generic helper that reads one column avoids this error.

Assignment to the tuple property with a single component produces:

```text
error: cannot assign value of type 'Position' to type 'Position'
```

A variadic setter method avoids this error. Tuple assignment works with two and four components in the ECS tests.

Neither probe produces the historical `signal 11 in emitPackExpansionIntoPack` error.

## ECS checks

`Tests/ECSTests/TypedQueryPackTests.swift` uses the real internal columns. The tests cover:

- Typed column binding through a generic factory.
- Reads with one, two, three, and four components.
- Writes through retained columns and reads after entity-handle writes.
- A nonzero row index and an unchanged neighboring entity.
- Component-event delivery and rejection of absent columns.

Both configurations pass:

```sh
xcb test "$PWD/Package.swift/ECS" -- --filter TypedQueryPackTests
xcb test "$PWD/Package.swift/ECS" -c Release -- --filter TypedQueryPackTests
```

The prototype preserves the storage-observation hooks. It does not establish a complete iterator design, structural-mutation safety, or compile-time membership checks for component-type subscripts.

Issues #3 and #6 can consider parameter packs without assuming that explicit overloads or macros are necessary.

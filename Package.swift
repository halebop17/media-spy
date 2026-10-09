// swift-tools-version: 6.0
// MediaSpy — native macOS media inspector built on libmediainfo (BSD-2).
// See docs/development-plan.md.
import PackageDescription

let package = Package(
    name: "MediaSpy",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MediaSpyKit", targets: ["MediaSpyKit"]),
        .executable(name: "mediaspy", targets: ["mediaspy"]),
        .executable(name: "MediaSpyApp", targets: ["MediaSpyApp"]),
    ],
    targets: [
        // C bridge to libmediainfo's plain-C interface (MediaInfoDLL_Static.h).
        // Resolved via pkg-config (Homebrew for dev; bundled xcframework later, see plan §8).
        .systemLibrary(
            name: "CMediaInfo",
            pkgConfig: "libmediainfo",
            providers: [.brew(["libmediainfo"])]
        ),
        // Shared core: engine wrapper, models, curated presentation fields.
        // All parsing lives here — app UI, CLI, and Finder extensions reuse it.
        .target(
            name: "MediaSpyKit",
            dependencies: ["CMediaInfo"]
        ),
        // Headless CLI — M1 verification harness and future Quick Action helper.
        .executableTarget(
            name: "mediaspy",
            dependencies: ["MediaSpyKit"]
        ),
        // SwiftUI app (Ember design). Named "MediaSpyApp" so its binary does
        // not collide with the "mediaspy" CLI on case-insensitive APFS.
        .executableTarget(
            name: "MediaSpyApp",
            dependencies: ["MediaSpyKit"]
        ),
        .testTarget(
            name: "MediaSpyKitTests",
            dependencies: ["MediaSpyKit"]
        ),
    ],
    // Swift 5 language mode: relaxed concurrency (app is @MainActor-driven UI).
    swiftLanguageModes: [.v5]
)

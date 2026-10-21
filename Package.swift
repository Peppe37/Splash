// swift-tools-version:5.10
import PackageDescription

// Splash: animated and procedural wallpapers for macOS (working name).
let package = Package(
    name: "Splash",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SplashCore", targets: ["SplashCore"]),
        .library(name: "SplashPlatform", targets: ["SplashPlatform"]),
        .executable(name: "splash", targets: ["splash"]),
        .executable(name: "splash-runner", targets: ["SplashRunner"]),
        .executable(name: "splash-editor", targets: ["SplashEditor"]),
    ],
    targets: [
        // Scene format, linter, performance policy. No UI, no side effects: easy to test.
        .target(name: "SplashCore"),
        // Web view, baker, desktop image and runner control: the parts that need AppKit, WebKit and AVFoundation.
        .target(name: "SplashPlatform", dependencies: ["SplashCore"]),
        // Command line tool, driven by people and by AI agents (init, lint, snapshot, bake, doctor).
        .executableTarget(name: "splash", dependencies: ["SplashCore", "SplashPlatform"]),
        // The light process that draws the wallpaper. No editor code in here.
        .executableTarget(name: "SplashRunner", dependencies: ["SplashCore", "SplashPlatform"]),
        // The window used to create and edit scenes. Closed once a scene is applied.
        .executableTarget(name: "SplashEditor", dependencies: ["SplashCore", "SplashPlatform"]),
        .testTarget(name: "SplashCoreTests", dependencies: ["SplashCore"]),
    ]
)

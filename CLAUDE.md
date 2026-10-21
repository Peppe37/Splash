# Splash: notes for Claude Code

Splash is a macOS app for animated and procedural wallpapers. Swift only, macOS 14+, GPL-3.0. "Splash" is a working name: see `docs/NAMING.md`.

## Read first

- `docs/ARCHITECTURE.md`: the pieces and why
- `docs/PERFORMANCE.md`: **the main constraint**. The wallpaper must be nearly free to run.
- `docs/SCENE_FORMAT.md`: `scene.json` and the `splash` JavaScript object
- `docs/AGENTS_INTEGRATION.md`: how agents are driven, and what was tested

## Commands

```sh
swift build                 # build everything
swift test                  # Swift Testing suites (XCTest is not required)
.build/debug/splash lint registry/presets/gradient-drift
.build/debug/splash presets export registry/presets   # after changing a preset: the registry is generated
xcodegen generate           # .app bundles; then xcodebuild -scheme SplashEditor
```

Needs a Swift 5.10+ toolchain. `swift test` needs Xcode's toolchain: if `xcode-select -p` points at the Command Line Tools, run it with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Rules

1. **Do not add work to the runner.** `SplashRunner` must stay event-driven: no timers, no polling, no network, no editor code. Any rule about when to draw goes in `PerformancePolicy` and gets a test.
2. **No new dependencies** without a strong reason. They must be permissive-licensed (MIT, BSD, Apache-2.0) because the project is GPL-3.0 and may be relicensed by its owner. No Node, no Python at runtime.
3. **`SplashCore` stays pure**: Foundation only, no AppKit, no UI. It is where tests live. Anything that needs AppKit, WebKit or AVFoundation goes in `SplashPlatform`.
4. **Scene code is untrusted.** Do not widen what a scene may do without a manifest permission and a linter rule.
5. **Never ask for or store an AI API key.** AI goes through the user's own agent CLI. A new agent adapter must be tested on a copy of a scene in another folder, and must be shown to edit only that folder, before it is enabled (OpenCode was switched off for failing this).
6. **Do not run an agent against files you care about.** `splash ask` and the editor's chat change files.
7. Keep documentation in step with code. If you change the scene format, update `docs/SCENE_FORMAT.md`, the linter and its tests together.
8. Comments explain why, not what. Code and docs are in English.

## Layout

See the end of `docs/ARCHITECTURE.md`.

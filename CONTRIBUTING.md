# Contributing to Splash

Thanks for wanting to help. Splash is pre-alpha: the structure is still moving, so for anything big, open a discussion before you write code.

## Ways to help without code

- Report a bug or ask for a feature with the issue templates.
- Make a **scene** and share it. Presets and scenes are the best contribution.
- Test on different Macs and macOS versions, and report CPU and memory use.
- Improve the documentation.

## Building

You need macOS 14 or newer and Xcode 16 or newer. The Command Line Tools can build, but `swift test` needs Xcode's toolchain (if `xcode-select -p` shows the Command Line Tools, prefix the command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`).

```sh
swift build
swift test
.build/debug/splash-editor      # the editor
```

If you change a preset in `Sources/SplashCore/Presets.swift`, regenerate the registry: `.build/debug/splash presets export registry/presets`. CI fails if it is out of date.

The `.app` bundles are generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) and need Xcode:

```sh
brew install xcodegen
xcodegen generate
open Splash.xcodeproj
```

The Xcode project is generated and not committed: change targets and settings in `project.yml`.

## Before you open a pull request

- Read [AGENTS.md](AGENTS.md): the rules (especially about performance and dependencies) apply to people too.
- `swift build` and `swift test` pass.
- If you change the scene format, update the linter, its tests and [docs/SCENE_FORMAT.md](docs/SCENE_FORMAT.md) together.
- If you add a scene, `splash lint <folder>` reports no errors, and it declares no permission it does not need.
- Add a line to [CHANGELOG.md](CHANGELOG.md) under **Unreleased**.

## Performance is a feature

A change that makes the runner do more work while idle will not be merged. If your change affects what runs in the background, say how much CPU and memory it uses, and how you measured it.

## License and CLA

Splash is [GPL-3.0](LICENSE). Contributions are accepted under the terms of the [CLA](CLA.md), which lets the maintainer also distribute the project under other terms. The CLA text is a draft and will be finalized before the repository accepts outside contributions.

New dependencies must be permissively licensed (MIT, BSD, Apache-2.0).

## Conduct

Be kind. See the [Code of Conduct](CODE_OF_CONDUCT.md).

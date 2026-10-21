# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.1.2-alpha] - 2026-10-21

### Fixed
- The wallpaper runner inside the app is now signed with the project's certificate too. In 0.1.1-alpha it kept an ad-hoc signature, because the signing step did not reach the folder it lives in. The release build now fails if any piece of the app is ad-hoc signed.

## [0.1.1-alpha] - 2026-10-21

### Added
- **Updates from inside the app.** When a new version is out, the library shows an Update button and Settings → About has **Update and restart**: it downloads the release from this repository, checks that it is signed with the same identity as the running app, replaces the app, opens it again and starts the wallpaper again if it was running. The editor asks GitHub once a day, while it is open (a single small request; switch it off in Settings → About). The wallpaper process never uses the network.
- `scripts/setup-signing.sh`, which creates the fixed signing certificate once and stores it as repository secrets.

### Changed
- Releases are signed with a fixed, self-signed certificate instead of an ad-hoc signature, so macOS recognises every update as the same app and keeps its permissions. Updating from 0.1.0-alpha (ad-hoc) to this version is done by hand: download the DMG.

## [0.1.0-alpha] - 2026-10-21

### Added
- First alpha. A library with real thumbnails, a flat editor close to HyperFrames' look, a prompt under the preview, an app icon.
- Scenes draw at the resolution the host asks for (`splash.detail`): full quality for pictures and recordings, reduced only for live wallpapers. Presets use fractions of the canvas, so they look the same at any size.
- A still picture of the scene is set as the real wallpaper under a moving one; the previous wallpaper is remembered and can be put back. New displays get it too.
- Website (`site/`) with the real scenes running live, built from the presets; DMG release workflow.
- Scene format v1 (`scene.json`) with parameters, tiers and permissions; linter; seven presets.
- `splash` command line tool: `init`, `presets`, `lint`, `snapshot`, `bake`, `ask`, `doctor`, `version`.
- `PerformancePolicy` and power settings (pause on battery, pause in Low Power Mode, battery frame rate).
- `splash-runner`: desktop-level wallpaper window per screen, live and baked tiers, menu bar item, single instance, driven by `state.json` and system notifications, no timers.
- Baker: seamless HEVC loops; static tier through the real desktop picture.
- `splash-editor`: scene library, live preview, parameters, apply (still, video, live), history with undo, drawing and pin comments, chat with an agent CLI, Settings.
- Agent bridge: Claude Code tested. Codex wired up, untested. OpenCode switched off (it edited files outside the scene).
- XcodeGen project: the editor app carries the runner app and the command line tool.
- Documentation, community files, CI and release workflows.
- Settings: power choices, and an About page with the version, feedback links, a manual update check and ways to support the project.
- Reviews, support and donation links, issue forms, Homebrew cask and a repeatable benchmark (`scripts/benchmark.sh`), set up the same way as Notcholino.

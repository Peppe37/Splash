# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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

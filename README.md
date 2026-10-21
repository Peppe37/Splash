<p align="center">
  <img src="site/assets/icon.png" width="112" alt="Splash logo">
</p>

<h1 align="center">Splash</h1>

<p align="center">
  <b>Animated wallpapers for macOS.</b><br>
  Pick a preset, tune it, or describe it to the AI agent you already use.<br>
  Free, open source (GPL-3.0), and light enough to forget it is running.
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-blue">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-SwiftUI-orange">
  <a href="LICENSE"><img alt="License: GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-blue"></a>
  <img alt="Status: pre-alpha" src="https://img.shields.io/badge/status-pre--alpha-lightgrey">
</p>

<p align="center">
  <a href="https://peppe37.github.io/Splash/">Website</a> ·
  <a href="https://github.com/Peppe37/Splash/releases/latest">Download</a> ·
  <a href="docs/ARCHITECTURE.md">Architecture</a> ·
  <a href="CHANGELOG.md">Changelog</a>
</p>

<p align="center">
  <img src="site/assets/shots/library.png" width="760" alt="The Splash library">
</p>

> **Pre-alpha.** It works on the development machine, but it is not signed or notarized, and some parts were built but not yet used by a person. See [known limits](#known-limits).

## What it is

A wallpaper in Splash is a **scene**: a small folder with a web page and a list of controls. There are three ways to get one, and they all end in the same kind of folder:

1. **A preset.** Pick one, move the controls. No AI.
2. **An algorithm.** The presets are procedural: gradients, waves, stars, ribbons, aurora.
3. **An AI agent.** Describe the wallpaper, or draw and pin comments on the preview. Splash runs the agent CLI you already have, inside the scene's folder. **No API key**: it uses that CLI's own login.

## Light by design

A wallpaper is on all day, so Splash puts a scene on the desktop in the cheapest way the scene allows:

| Way | What runs | Cost (measured once, one MacBook Pro, rough) |
| --- | --- | --- |
| **Still** | One picture set as the real macOS wallpaper | Nothing. No process |
| **Loop** | A recorded HEVC loop, played by the system's decoder | Runner about 14 MB and 1% CPU, no web view |
| **Live** | The scene drawn in real time | About 170 MB with web processes, about 7% of a core |

The app you design in is separate from the wallpaper process, so you can close it. The runner has no timers: it pauses when covered, when the screen sleeps or locks, on Low Power Mode, and when the Mac is hot, and lowers its frame rate on battery. More in [docs/PERFORMANCE.md](docs/PERFORMANCE.md).

No telemetry. No network unless a scene asks for it.

## Install

There is no release yet. Build it from source (macOS 14+, Xcode 16+):

```sh
git clone https://github.com/Peppe37/Splash.git
cd Splash
swift build
.build/debug/splash-editor
```

Releases will be a DMG. The first time you open an app that is not notarized, Control-click it and choose **Open**, or use **Open Anyway** in System Settings, Privacy & Security.

In the editor: pick a preset, change the controls, choose **Still**, **Loop** or **Live**, press **Apply**, and close the window. The wallpaper keeps going in the menu bar. **Draw on preview** (pencil icon) lets you draw and pin comments to send with an AI request.

From a terminal, the same scenes:

```sh
splash presets                                  # list the presets
splash init my-scene --preset aurora
splash lint my-scene
splash snapshot my-scene out.png --time 5       # a picture of the scene
splash bake my-scene out.mov                    # one seamless HEVC loop
splash ask my-scene "make it slower and warmer" # needs an agent CLI
splash-runner my-scene                          # show it live on the desktop (Ctrl+C to stop)
```

## Known limits

- Not signed or notarized. No installer yet. Start at login only works when the runner is built as an app (`xcodegen generate`).
- Only **Claude Code** is enabled as an agent. Codex is wired up but untested. OpenCode is switched off: in testing it edited files outside the scene. See [docs/AGENTS_INTEGRATION.md](docs/AGENTS_INTEGRATION.md).
- A moving wallpaper is a window at the desktop level (macOS has no public way to animate the real wallpaper). Splash also sets a picture of the scene as the real wallpaper, so Mission Control and new displays match, and it can put your previous wallpaper back. How well this behaves with Spaces, Stage Manager and virtual displays has not been tested enough.
- Applying a still picture, the drawing overlay and Settings were built but not clicked through by a person yet.
- Scenes that use WebGL may need `preserveDrawingBuffer: true` to be recorded.
- Planned, not built: Metal runtime, audio-reactive scenes, weather and time-of-day scenes, screen saver.

## Documentation

- [Architecture](docs/ARCHITECTURE.md), [Scene format](docs/SCENE_FORMAT.md), [Performance](docs/PERFORMANCE.md)
- [AI agents](docs/AGENTS_INTEGRATION.md): how the chat drives the agent CLIs, and what was tested
- [Roadmap](docs/ROADMAP.md), [Naming](docs/NAMING.md)
- [Contributing](CONTRIBUTING.md), [Code of Conduct](CODE_OF_CONDUCT.md), [Security](SECURITY.md)

## Inspiration

The agent-driven workflow (skills, a non-interactive CLI the agent can call, live preview, a registry of reusable blocks) follows [HyperFrames](https://github.com/heygen-com/hyperframes) by HeyGen, which does it for video, and so does the flat, border-first look of the app. Splash does it for wallpapers.

## License

[GPL-3.0](LICENSE). Contributions are accepted under the [CLA](CLA.md) (a draft), so the author can also offer paid extras that he writes himself.

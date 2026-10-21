# Architecture

Splash turns a **scene** (a folder with code and parameters) into a wallpaper. Two things drive the design:

1. **Every way of making a scene produces the same folder.** Presets, sliders, algorithms and AI agents all write or edit the same files. So the AI is optional and never a special case.
2. **The wallpaper must cost almost nothing.** Creating a scene may use a lot of resources. Showing it must not.

## The pieces

```
              ┌────────────── Editor (splash-editor) ──────────────┐
              │ preview · parameters · chat · drawing · history    │
              └───────┬───────────────────────────┬────────────────┘
                      │ edits files               │ spawns
                      ▼                           ▼
              ┌──────────────┐            ┌──────────────────┐
              │ Scene folder │◄───────────│ Agent CLI        │
              │ scene.json   │  edits     │ claude / codex / │
              │ index.html…  │            │ opencode         │
              └──────┬───────┘            └──────────────────┘
                     │ read by
        ┌────────────┼───────────────┐
        ▼            ▼               ▼
   splash (CLI)   Runner         Baker
   init, lint,    desktop        scene → image / HEVC loop
   doctor…        window         (static and baked tiers)
```

| Target | Kind | Role |
| --- | --- | --- |
| `SplashCore` | library | Scene format, linter, presets, library on disk, parameter values, history, performance policy, agent adapters, runtime script. Foundation only: no AppKit, no UI. |
| `SplashPlatform` | library | What needs AppKit, WebKit and AVFoundation: the scene web view, the off-screen renderer, the baker, the desktop image, runner control. |
| `splash` | executable | Command line tool (`init`, `lint`, `presets`, `snapshot`, `bake`, `ask`, `doctor`). Non-interactive, so people, scripts and AI agents can use it. |
| `SplashRunner` | executable | The light process that draws the wallpaper. Knows nothing about editing. |
| `SplashEditor` | executable | The creation window. Can be closed once a scene is applied. |

Everything is Swift. There is no Node dependency on the user's Mac. (A Rust core for headless baking and CPU generators is possible later; see the roadmap.)

## Scenes and runtimes

A scene declares a **runtime**:

- `web`: HTML, CSS and JavaScript in a `WKWebView`. Agents write this well, it can use WebGL and three.js, and it needs no build step. This is the first runtime.
- `metal`: a Metal shader drawn by the runner with no web process. Much less memory. Planned right after the web runtime.

The runner injects a small SDK (`SceneRuntimeScript`) before the scene's own code. It exposes `splash.params`, `splash.time`, `splash.onParams`, `splash.onPause`, and replaces `requestAnimationFrame` with a version capped by the frame rate the system allows. See [SCENE_FORMAT.md](SCENE_FORMAT.md).

## Apply tiers

A scene lists the tiers it supports, preferred one first: `static`, `baked`, `live`. At apply time Splash chooses the lightest one allowed. The **baker** renders the scene (it can seek to a time `t`, because scenes are driven by `splash.time`) into either a still image or a seamless HEVC loop of `loopSeconds`.

- `static`: set with `NSWorkspace.setDesktopImageURL`. For scenes that change slowly (time of day, weather), a tiny scheduled job regenerates the image.
- `baked`: played with AVFoundation, hardware decoded.
- `live`: the runner draws in real time. Required for audio-reactive and interactive scenes.

## The runner

`splash-runner` is an accessory app (no Dock icon, no menus) with one desktop-level, click-through window per screen, visible on all Spaces.

It is event-driven. `SystemMonitor` listens for thermal state, Low Power Mode, power source changes, screen sleep and lock, and window occlusion. Each change goes through `PerformancePolicy.decide`, a pure function that returns `run(fps)`, `pause` or `suspend`. `suspend` destroys the web view and its processes to give the memory back. There are no timers and no polling.

macOS has no API to replace the wallpaper layer, so a desktop-level window is the standard technique. `static` is the one exception: it uses the real wallpaper.

## Editor and runner talk through two files and three messages

The editor never keeps the runner alive and the runner never watches the disk.

- **`state.json`** (in `~/Library/Application Support/Splash`, or `$SPLASH_HOME`): what to show. `{ sceneDirectory, tier, mediaPath? }`. Written by the editor.
- **Messages** over the system's distributed notification center: `reload` (read `state.json` again), `values` (new parameter values for the live scene), `settings` (power settings changed), `quit`.
- **`runner.pid`**: only one runner runs. A second one asks the first to reload and exits. A static wallpaper needs no runner, so the runner quits when it reads one.

Applying a scene:

| Tier | What the editor does | What runs afterwards |
| --- | --- | --- |
| `static` | Draws the scene once off screen, saves a PNG, sets it with `NSWorkspace.setDesktopImageURL` | Nothing |
| `baked` | Renders one loop frame by frame into an HEVC `.mov` (`Baker`), writes `state.json`, starts the runner | The runner plays the video with `AVPlayerLooper`. No web view |
| `live` | Writes `state.json`, starts the runner | The runner draws the scene in a web view |

The baker works because the SDK can fix the scene's clock (`splash._renderAt(t)`) and run one frame, so frames are exact and the first frame follows the last.

## The editor

SwiftUI, one window with the title bar folded into the content. Visual rules: flat surfaces separated by 1 px borders, no shadows, warm neutrals with near-black as the strongest contrast, small radii, colour only for status (see `Theme.swift`).

- **Library**: your scenes and the presets as cards with a real picture of the scene. Pictures are drawn by the same code as the wallpaper, one at a time, and cached on disk until the scene's files change (`ThumbnailStore`).
- **Editor**: a large preview, an AI prompt under it, and an inspector with **Controls**, **Versions** and **Details**. Still, Loop or Live is chosen next to **Apply**.
- **Controls**: built from `scene.json`. Live wallpapers follow the sliders.
- **AI prompt**: a chat with an agent CLI (see [AGENTS_INTEGRATION.md](AGENTS_INTEGRATION.md)). Drawings and numbered pin comments on the preview are composed with a frame of the scene into a PNG inside the scene folder and sent with the text.
- **Versions**: a snapshot of the scene folder before every AI turn and every restore (`.splash/history`, last 50). Any change can be undone.

The scene folder carries an `AGENTS.md` (and a `CLAUDE.md` that imports it) with the rules and the SDK, so any agent knows how to work in it.

## Resolution

A scene does not choose its own resolution. The host passes `splash.detail`: canvas pixels are device pixels divided by it. Pictures and recordings use 1 (every pixel; quality is free because the result is kept), the editor preview uses 1.25, and a live wallpaper uses 2. Scenes draw in fractions of the canvas, so they look the same at any size.

## The desktop

macOS has no public way to animate the real wallpaper, so a moving scene is a window at the desktop level, under icons and windows. That has costs: Mission Control, sliding between Spaces and a just-connected display show the real wallpaper. So applying a live or baked scene also renders a still picture of it (`stillTime`, a quarter into the loop) and sets that as the real wallpaper on every display and every Space. The runner sets it again when displays change.

**Every Space.** `NSWorkspace.setDesktopImageURL` only changes the Space on screen. `WallpaperStore` lets macOS write that entry, then copies it to every other Space, display and display default in `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`, and restarts the wallpaper agent (`launchctl kickstart`, or ending the agent when System Integrity Protection refuses that; launchd starts it again). The format is not documented, so the code copies what macOS wrote and never builds an entry itself; if that entry is not found it changes nothing. The copy is a pure function with tests. The original file is saved once (`wallpaper-store-backup.plist`) and put back by "Put back my previous wallpaper" and `splash desktop restore`. Settings → Desktop switches it off.

## Security

- Scene code is untrusted. It runs in a web view with a non-persistent data store, and every navigation that is not a file inside the scene folder is cancelled unless the scene has `permissions.network`.
- Permissions (`network`, `audio`, `location`) are declared in `scene.json`, shown to the user, and checked by the linter.
- The agent runs with the scene folder as its working directory. It runs with the user's own login and permissions, so the editor must show what the agent does, and must never apply a scene the user has not seen.
- Shared scenes are installed from the registry only after the user reviews their permissions.

## Repository layout

```
Sources/SplashCore/     scene format, linter, presets, library, history, policy, agents
Sources/SplashPlatform/ web view, off-screen renderer, baker, desktop image, runner control
Sources/splash/         command line tool
Sources/SplashRunner/   wallpaper process
Sources/SplashEditor/   editor
Tests/                  Swift Testing suites
registry/presets/       bundled scenes (generated: `splash presets export registry/presets`)
skills/splash/          skill for AI agents (router + rules)
docs/                   documentation
project.yml             XcodeGen spec for the .app bundles
```

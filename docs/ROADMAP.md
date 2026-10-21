# Roadmap

Nothing here has a date.

## Done (working on the development machine)

- Scene format v1, linter, `splash` CLI: `init`, `lint`, `presets`, `snapshot`, `bake`, `ask`, `doctor`
- Seven presets (gradient drift, aurora, starfield, waves, ribbons, dusk, blank)
- Performance policy with tests; power settings (pause on battery, pause in Low Power Mode, battery frame rate)
- Runner: desktop window per screen, live tier and baked tier, menu bar item (pause, open editor, start at login), one instance, driven by `state.json` and messages, shows a still picture when paused
- Baker: seamless HEVC loop, checked by comparing the wrap-around frame step with a normal step
- Editor: library with real thumbnails, live preview, controls, apply as still, loop or live, versions with undo, drawing and pin comments, chat; flat HyperFrames-like design; app icon
- A still picture of the scene under every moving wallpaper, the previous wallpaper remembered and restorable
- Full-resolution pictures and recordings; presets resolution-independent (`splash.detail`)
- Website and DMG release workflow
- Agent adapter: Claude Code tested; Codex written but untested; OpenCode switched off
- App bundles through XcodeGen (editor with the runner and the CLI inside), CI, documentation

## To do before 0.1

- Click through the whole editor as a person: static apply, the drawing overlay, Settings, deleting and renaming scenes
- Check the desktop window against Spaces, Stage Manager, Mission Control and virtual displays
- Test Codex, and find out why OpenCode edits the wrong folder
- Release-build performance measurements, then a CI benchmark
- Runner as a proper login item (`SMAppService` needs the runner as an app bundle: works from the Xcode build, untested)
- Signed and notarized builds, a DMG
- An app icon and a menu bar icon

## 0.2

- Skill packaged for Claude Code, Codex and OpenCode
- Chat history kept between launches
- Scenes folder import and export (`.splashscene`)
- More presets, including a 3D one (three.js bundled in the scene)

## 0.3: extras

- Metal runtime (no web process, much less memory)
- Audio-reactive scenes (opt in, live only, off on battery)
- Time of day and weather scenes, regenerated on a schedule (static tier)
- Screen saver target (`.saver`)
- Video export (the baker already does most of it)
- Registry: share and install scenes, with a permissions review
- Different scene per screen

## Later, maybe

- A Rust core for headless baking and CPU generators, if Swift proves limiting
- Mac App Store release and a paid tier (needs the CLA in place, and a check of the App Store terms against the GPL)

## Open questions

- Final name ([NAMING.md](NAMING.md))
- Which agent protocol to standardize on (per-CLI adapters or ACP)

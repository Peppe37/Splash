# Working on a Splash scene

This folder is one animated wallpaper. Edit the files here, then check your work with the CLI.

## Files

- `scene.json`: name, tiers, fps, permissions and the list of adjustable parameters.
- `index.html` (the `entry`): the scene itself. Plain HTML, CSS and JavaScript. No build step.

## Rules

1. **Be light.** This is a wallpaper that stays on for days. Prefer slow motion, few draw calls, small canvases scaled up, and no work while nothing changes. Default `fps` is 30. Do not raise it without a reason.
2. **Never use `setInterval` or your own timers for animation.** Use `requestAnimationFrame`. Splash replaces it with a version that follows the system's power rules and pauses the scene when it is hidden.
3. **Make it loop.** If the scene lists the `baked` tier, one loop of `loopSeconds` must start and end on the same frame, so the video loop has no jump. Drive motion with `splash.time` only, use whole numbers of cycles per loop, and make any speed parameter a whole number (min 1, step 1).
4. **No network.** Bundle fonts, models and textures in this folder. If you really need the network, set `permissions.network` to true and say why in `description`.
5. **Every adjustable value is a parameter.** Declare it in `scene.json` under `params` (types: `number` with `min` and `max`, `color` like `#aa33ff`, `bool`, `choice` with `options`). Read it with `splash.params.<key>`, and react to changes with `splash.onParams(callback)`.
6. Keep the scene readable. Someone will edit it by hand later.
7. Only read and change files inside this folder.

## The `splash` object

- `splash.params`: current parameter values.
- `splash.time`: seconds since the scene started, not counting pauses.
- `splash.fps`: current frame cap.
- `splash.onParams(cb)`: call `cb` now and on every change.
- `splash.onPause(cb)`: `cb(true)` when paused, `cb(false)` when resumed.

## Check your work

```sh
splash lint .
splash snapshot . out.png --time 3
```

`snapshot` draws the scene at a moment and saves a picture, so you can look at your work. Delete `out.png` when you are done. Fix every lint error. Treat warnings as advice. When the user sends a screenshot with drawings or comments on it, change only what they point at.
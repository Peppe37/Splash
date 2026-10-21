# Scene format

A scene is a folder (to be shared as a `.splashscene` package, which is the same folder zipped). Format version: **1**.

```
my-scene/
  scene.json     required
  index.html     the entry file (web runtime)
  …              scripts, shaders, textures, models: everything the scene needs
  AGENTS.md      rules for AI agents (written by `splash init`)
  CLAUDE.md      imports AGENTS.md for Claude Code
  .splash/       Splash's own data: parameter values, history, drawings. Not part of the scene when shared.
```

## scene.json

```json
{
  "schemaVersion": 1,
  "id": "gradient-drift",
  "name": "Gradient drift",
  "description": "Soft colour blobs that drift slowly.",
  "runtime": "web",
  "entry": "index.html",
  "tiers": ["baked", "live"],
  "fps": 30,
  "loopSeconds": 20,
  "permissions": { "network": false, "audio": false, "location": false },
  "params": [
    { "key": "colorA", "label": "Colour A", "type": "color", "default": "#5b3df5" },
    { "key": "speed", "label": "Speed", "type": "number", "default": 1, "min": 0.1, "max": 3, "step": 0.1 }
  ]
}
```

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Lowercase words joined by dashes. |
| `name` | yes | Shown to the user. |
| `runtime` | no | `web` (default) or `metal`. |
| `entry` | no | Main file, relative to the folder. Default `index.html`. |
| `tiers` | no | Ways it can be applied, preferred first: `static`, `baked`, `live`. Default `["baked", "live"]`. |
| `fps` | no | Frame rate cap while live, 1 to 60. Default 30. Lower is lighter. |
| `loopSeconds` | for `baked` | Length of one seamless loop. |
| `permissions` | no | All `false` by default. `audio` forces `tiers: ["live"]`. |
| `params` | no | Adjustable values. The editor builds its controls from this list. |

### Parameter types

| `type` | `default` | Extra fields |
| --- | --- | --- |
| `number` | a number | `min`, `max` (required), `step` |
| `color` | `"#rrggbb"` | |
| `bool` | `true` / `false` | |
| `choice` | one of `options` | `options` (required, non-empty) |

## The `splash` object (web runtime)

Injected before the scene's code.

| Member | Meaning |
| --- | --- |
| `splash.params` | Current parameter values, by key. |
| `splash.time` | Seconds since the scene started, not counting pauses. Drive animation from this so the baker can seek. |
| `splash.fps` | Current frame cap. |
| `splash.paused` | Whether drawing is paused. |
| `splash.onParams(cb)` | Calls `cb(params)` now and on every change. |
| `splash.onPause(cb)` | Calls `cb(true)` on pause and `cb(false)` on resume. |

To bake a seamless loop: drive everything from `splash.time`, use whole numbers of cycles per `loopSeconds`, make any speed parameter a whole number (min 1, step 1), and use a fixed seed for random values. Do not keep state between frames that depends on earlier frames (trails, simulations): the baker draws frames out of order.

`requestAnimationFrame` is replaced by a version capped at `splash.fps` that stops while paused. Do not use `setInterval` for animation.

## Files in a scene

A scene can bring files: put them in `assets/` and load them with relative paths (`assets/fox.svg`). SVG and PNG with a transparent background suit characters and logos. A `<video autoplay muted loop playsinline>` plays by itself, as long as it is muted; a scene with a video can only be `live`, because the baker cannot step a video frame by frame. `.splash/references/` is not part of the scene: it holds files that were only shown to an agent.

## Rules `splash lint` checks

Errors: wrong `schemaVersion`; bad `id`; empty `name`; missing or escaping `entry`; empty `tiers`; `baked` without `loopSeconds`; `fps` outside 1 to 60; `audio` with a tier other than `live`; duplicate param keys; bad param defaults or ranges; remote URLs in code when `permissions.network` is false.
Warnings: `fps` above 30; a `<video>` in a scene that offers the loop or still tier; an `assets/` folder over 100 MB. Addresses inside an SVG (`xmlns="http://www.w3.org/…"`) are not counted as network use.

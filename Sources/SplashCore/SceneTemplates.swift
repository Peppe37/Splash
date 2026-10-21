import Foundation

/// Files written by `splash init`.
public enum SceneTemplates {
    public static func manifest(id: String, name: String) -> SceneManifest {
        SceneManifest(
            id: id,
            name: name,
            description: "Soft colour blobs that drift slowly.",
            tiers: [.baked, .live],
            fps: 30,
            loopSeconds: 20,
            params: [
                SceneParam(key: "colorA", label: "Colour A", type: .color, default: .string("#5b3df5")),
                SceneParam(key: "colorB", label: "Colour B", type: .color, default: .string("#f5568b")),
                SceneParam(key: "colorC", label: "Colour C", type: .color, default: .string("#2ec4b6")),
                SceneParam(key: "speed", label: "Speed", type: .number, default: .number(1), min: 1, max: 3, step: 1),
            ]
        )
    }

    /// A small scene that works with no AI: three blurred blobs on slow loops. Everything is bundled, no network.
    public static let indexHTML = #"""
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        html, body { margin: 0; height: 100%; overflow: hidden; background: #000; }
        canvas { display: block; width: 100%; height: 100%; }
      </style>
    </head>
    <body>
    <canvas id="c"></canvas>
    <script>
      // Soft blobs, so it draws at a low resolution and lets the browser scale it up: the blur hides it, and it costs far less.
      const canvas = document.getElementById("c");
      const ctx = canvas.getContext("2d");
      const blobs = [
        { key: "colorA", x: 0.25, y: 0.30, r: 0.55, phase: 0.0 },
        { key: "colorB", x: 0.75, y: 0.35, r: 0.50, phase: 2.1 },
        { key: "colorC", x: 0.50, y: 0.80, r: 0.60, phase: 4.2 },
      ];
      const LOOP = 20; // seconds, same as loopSeconds in scene.json

      function resize() {
        // Soft gradients: a quarter of the resolution the host asks for is plenty.
        const divisor = splash.detail * 4;
        canvas.width = Math.max(64, Math.round(window.innerWidth * window.devicePixelRatio / divisor));
        canvas.height = Math.max(36, Math.round(window.innerHeight * window.devicePixelRatio / divisor));
      }
      window.addEventListener("resize", resize);
      resize();

      function draw() {
        const params = splash.params;
        const t = (splash.time * params.speed) % LOOP;
        const angle = (t / LOOP) * Math.PI * 2;
        ctx.fillStyle = "#000";
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.globalCompositeOperation = "lighter";
        for (const blob of blobs) {
          const x = (blob.x + 0.12 * Math.cos(angle + blob.phase)) * canvas.width;
          const y = (blob.y + 0.12 * Math.sin(angle + blob.phase)) * canvas.height;
          const radius = blob.r * canvas.height;
          const gradient = ctx.createRadialGradient(x, y, 0, x, y, radius);
          gradient.addColorStop(0, params[blob.key] + "cc");
          gradient.addColorStop(1, params[blob.key] + "00");
          ctx.fillStyle = gradient;
          ctx.fillRect(0, 0, canvas.width, canvas.height);
        }
        ctx.globalCompositeOperation = "source-over";
        requestAnimationFrame(draw);
      }
      requestAnimationFrame(draw);
    </script>
    </body>
    </html>
    """#

    /// Instructions for AI agents, written into every new scene folder.
    public static let agentsMarkdown = #"""
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

    ## Files the user gives you

    - Files in `assets/` are for the scene: load the file itself with a relative path (`assets/hero.svg`), in an `<img>` or drawn on the canvas. Do not redraw its shapes by hand. Keep it where it is.
    - Files in `.splash/references/` are only for you to look at. Never use them in the scene.
    - For characters, logos and props prefer SVG, or PNG with a transparent background. Keep files small.
    - A video can play as a layer: `<video autoplay muted loop playsinline src="assets/clip.mp4">`. It must be muted. A scene with a video can only be `live`: set `tiers` to `["live"]`, because a video cannot be recorded frame by frame.
    - You cannot play a video, but pictures taken from it are in `.splash/references/`. Look at those.

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
    """#
}

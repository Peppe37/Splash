---
name: splash
description: Create or edit a Splash animated wallpaper scene (scene.json plus an HTML/JS entry). Use when the user asks for a wallpaper, background, procedural animation or shader for Splash, or when the working directory contains a scene.json with a splash runtime.
---

# Splash scene

A Splash scene is a folder: `scene.json` and a web entry (`index.html` and whatever it loads). Your job is to write or change those files, then check them with `splash lint .`.

The folder's own `AGENTS.md` has the full rules and the `splash` JavaScript object. Read it first. The essentials:

1. **Be light.** This runs for days. Slow motion, few draw calls, small canvases scaled up, no work while nothing changes. `fps` is 30 unless there is a reason.
2. **Animate from `splash.time` and `requestAnimationFrame`.** Never `setInterval`.
3. **Loop seamlessly** when the `baked` tier is listed: one `loopSeconds` loop must end on its first frame.
4. **No network.** Bundle everything. Ask for `permissions.network` only if unavoidable.
5. **Every adjustable value is a `params` entry** in `scene.json`, read through `splash.params`.
6. Only read and change files inside the scene folder you were started in.
7. Run `splash lint .` and fix every error before you say you are done. `splash snapshot . out.png --time 3` draws a picture you can look at.

## Choosing the approach

Pick the lightest technique that gives the look:

- **Gradients, blobs, soft light**: 2D canvas at low resolution (about 1/8 of the screen), scaled up. The blur hides it.
- **Noise, flow fields, plasma**: a fragment shader on one full-screen quad (WebGL), or a low-resolution canvas with precomputed noise.
- **Particles**: a fixed small count, typed arrays, one draw call.
- **3D**: three.js bundled in the folder (no CDN), simple geometry, no real-time shadows, capped pixel ratio at 1 or 1.5.
- **Slowly changing scenes** (time of day, weather): declare `"tiers": ["static"]` and draw one frame; the app regenerates it on a schedule.

## When the user sends a drawing or comments

An annotated image and a list of comments (`x`, `y` as fractions of the frame, optional `time`, `text`) come with the request. Change only what they point at. If a comment is unclear, make the most likely small change and say what you assumed.

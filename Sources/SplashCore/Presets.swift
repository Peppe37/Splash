import Foundation

/// A scene that ships with the app. Presets are plain scenes: copying one gives the user a folder they can edit by hand or with an agent.
public struct Preset: Sendable {
    public let id: String
    public let summary: String
    public let manifest: SceneManifest
    public let files: [String: String]

    public var name: String { manifest.name }

    /// Writes the scene, with its `AGENTS.md` and `CLAUDE.md`, into `directory` under a new id and name.
    @discardableResult
    public func install(at directory: URL, id newID: String? = nil, name newName: String? = nil) throws -> Scene {
        var manifest = self.manifest
        if let newID { manifest.id = newID }
        if let newName { manifest.name = newName }
        try Scene.write(manifest, to: directory)
        for (path, content) in files {
            let url = directory.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        try SceneTemplates.agentsMarkdown.write(to: directory.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        // Claude Code reads CLAUDE.md, not AGENTS.md; the import keeps one source of truth.
        try "@AGENTS.md\n".write(to: directory.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
        return Scene(directory: directory, manifest: manifest)
    }
}

public enum Presets {
    public static let all: [Preset] = [gradientDrift, aurora, starfield, waves, ribbons, dusk, blank]

    public static func find(_ id: String) -> Preset? { all.first { $0.id == id } }

    /// Page shell shared by the canvas presets. The canvas size comes from the host (`splash.detail`): every device pixel when recording
    /// or taking a picture, half of them for a live wallpaper. `soft` makes it coarser still for scenes made only of soft gradients,
    /// where the blur hides the loss. Scenes draw in fractions of the canvas, so they look the same at any size.
    static func page(soft: Double, script: String) -> String {
        """
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
        const canvas = document.getElementById("c");
        const ctx = canvas.getContext("2d");
        const SOFT = \(soft);
        const TAU = Math.PI * 2;
        function resize() {
          const divisor = splash.detail * SOFT;
          canvas.width = Math.max(64, Math.round(window.innerWidth * window.devicePixelRatio / divisor));
          canvas.height = Math.max(36, Math.round(window.innerHeight * window.devicePixelRatio / divisor));
        }
        window.addEventListener("resize", resize);
        resize();
        function rgb(hex) { return [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16)); }
        function mix(a, b, f) { const x = rgb(a), y = rgb(b); return "rgb(" + x.map((v, i) => Math.round(v + (y[i] - v) * f)).join(",") + ")"; }
        \(script)
        </script>
        </body>
        </html>
        """
    }

    // MARK: - Presets

    static let gradientDrift = Preset(
        id: "gradient-drift",
        summary: "Soft colour blobs that drift slowly.",
        manifest: SceneTemplates.manifest(id: "gradient-drift", name: "Gradient drift"),
        files: ["index.html": SceneTemplates.indexHTML]
    )

    static let aurora = Preset(
        id: "aurora",
        summary: "Slow northern-lights bands over a dark sky.",
        manifest: SceneManifest(
            id: "aurora", name: "Aurora", description: "Slow northern-lights bands over a dark sky.",
            tiers: [.baked, .live], fps: 30, loopSeconds: 24,
            params: [
                SceneParam(key: "colorA", label: "Colour A", type: .color, default: .string("#27e1a0")),
                SceneParam(key: "colorB", label: "Colour B", type: .color, default: .string("#7a5cff")),
                SceneParam(key: "sky", label: "Sky", type: .color, default: .string("#050914")),
                SceneParam(key: "speed", label: "Speed", type: .number, default: .number(1), min: 1, max: 3, step: 1),
            ]),
        files: ["index.html": page(soft: 1, script: #"""
        const LOOP = 24;
        const BANDS = 4, SEGMENTS = 180;
        function draw() {
          const p = splash.params, w = canvas.width, h = canvas.height;
          const angle = TAU * p.speed * splash.time / LOOP;
          ctx.globalCompositeOperation = "source-over";
          ctx.fillStyle = p.sky;
          ctx.fillRect(0, 0, w, h);
          ctx.globalCompositeOperation = "lighter";
          for (let b = 0; b < BANDS; b++) {
            const base = h * (0.28 + 0.11 * b), thick = h * (0.22 + 0.03 * b);
            const top = [];
            for (let i = 0; i <= SEGMENTS; i++) {
              const u = i / SEGMENTS;
              const y = base + h * 0.08 * Math.sin(u * TAU * 1.8 * (b + 1) + angle * (b % 2 + 1) + b) + h * 0.03 * Math.sin(u * TAU * 4.4 + angle * 2 + b * 2);
              top.push([u * w, y]);
            }
            ctx.beginPath();
            ctx.moveTo(top[0][0], top[0][1]);
            top.forEach(pt => ctx.lineTo(pt[0], pt[1]));
            for (let i = top.length - 1; i >= 0; i--) ctx.lineTo(top[i][0], top[i][1] + thick);
            ctx.closePath();
            const gradient = ctx.createLinearGradient(0, base - h * 0.1, 0, base + thick);
            const color = mix(p.colorA, p.colorB, b / (BANDS - 1));
            // A smooth rise and fall of the glow: a single bright stop would show as a visible stripe.
            const rgbaColor = color.replace("rgb", "rgba");
            for (let stop = 0; stop <= 10; stop++) {
              const t = stop / 10, glow = Math.pow(Math.sin(Math.PI * Math.pow(t, 0.8)), 1.6) * 0.55;
              gradient.addColorStop(t, rgbaColor.replace(")", "," + glow.toFixed(3) + ")"));
            }
            ctx.fillStyle = gradient;
            ctx.fill();
          }
          requestAnimationFrame(draw);
        }
        requestAnimationFrame(draw);
        """#)]
    )

    static let starfield = Preset(
        id: "starfield",
        summary: "Stars drifting past, as if flying through space.",
        manifest: SceneManifest(
            id: "starfield", name: "Starfield", description: "Stars drifting past, as if flying through space.",
            tiers: [.baked, .live], fps: 30, loopSeconds: 30,
            params: [
                SceneParam(key: "stars", label: "Star colour", type: .color, default: .string("#ffffff")),
                SceneParam(key: "space", label: "Space", type: .color, default: .string("#04050d")),
                SceneParam(key: "speed", label: "Speed", type: .number, default: .number(1), min: 1, max: 3, step: 1),
            ]),
        files: ["index.html": page(soft: 1, script: #"""
        const LOOP = 30, COUNT = 260;
        // A fixed seed keeps every frame, and every recording, identical.
        let seed = 7;
        function rand() { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }
        const stars = Array.from({ length: COUNT }, () => ({ x: rand() * 2 - 1, y: rand() * 2 - 1, phase: rand(), rate: 1 + Math.floor(rand() * 2) }));
        function draw() {
          const p = splash.params, w = canvas.width, h = canvas.height;
          ctx.fillStyle = p.space;
          ctx.fillRect(0, 0, w, h);
          ctx.fillStyle = p.stars;
          for (const s of stars) {
            const z = (s.phase + s.rate * p.speed * splash.time / LOOP) % 1;
            const x = w / 2 + s.x * z * w * 0.75, y = h / 2 + s.y * z * h * 0.75;
            const size = Math.max(1, (0.0008 + z * 0.0034) * h);
            ctx.globalAlpha = Math.min(1, z * 1.4);
            ctx.beginPath();
            ctx.arc(x, y, size / 2, 0, TAU);
            ctx.fill();
          }
          ctx.globalAlpha = 1;
          requestAnimationFrame(draw);
        }
        requestAnimationFrame(draw);
        """#)]
    )

    static let waves = Preset(
        id: "waves",
        summary: "Layered waves rolling at different speeds.",
        manifest: SceneManifest(
            id: "waves", name: "Waves", description: "Layered waves rolling at different speeds.",
            tiers: [.baked, .live], fps: 30, loopSeconds: 20,
            params: [
                SceneParam(key: "colorA", label: "Top colour", type: .color, default: .string("#4cc9f0")),
                SceneParam(key: "colorB", label: "Bottom colour", type: .color, default: .string("#3a0ca3")),
                SceneParam(key: "speed", label: "Speed", type: .number, default: .number(1), min: 1, max: 3, step: 1),
            ]),
        files: ["index.html": page(soft: 1, script: #"""
        const LOOP = 20, LAYERS = 6, SEGMENTS = 240;
        function draw() {
          const p = splash.params, w = canvas.width, h = canvas.height;
          const angle = TAU * p.speed * splash.time / LOOP;
          ctx.fillStyle = p.colorA;
          ctx.fillRect(0, 0, w, h);
          for (let i = 0; i < LAYERS; i++) {
            const f = i / (LAYERS - 1);
            ctx.beginPath();
            ctx.moveTo(0, h);
            for (let k = 0; k <= SEGMENTS; k++) {
              const u = k / SEGMENTS;
              const y = h * (0.3 + 0.12 * i) + h * 0.05 * Math.sin(u * TAU * (2.4 + 0.8 * i) + angle * (i % 3 + 1) * (i % 2 ? 1 : -1) + i * 1.7);
              ctx.lineTo(u * w, y);
            }
            ctx.lineTo(w, h);
            ctx.closePath();
            ctx.fillStyle = mix(p.colorA, p.colorB, f);
            ctx.fill();
          }
          requestAnimationFrame(draw);
        }
        requestAnimationFrame(draw);
        """#)]
    )

    static let ribbons = Preset(
        id: "ribbons",
        summary: "Thin glowing lines flowing across the screen.",
        manifest: SceneManifest(
            id: "ribbons", name: "Ribbons", description: "Thin glowing lines flowing across the screen.",
            tiers: [.baked, .live], fps: 30, loopSeconds: 24,
            params: [
                SceneParam(key: "colorA", label: "Colour A", type: .color, default: .string("#ff4d8d")),
                SceneParam(key: "colorB", label: "Colour B", type: .color, default: .string("#4d9bff")),
                SceneParam(key: "background", label: "Background", type: .color, default: .string("#0a0714")),
                SceneParam(key: "speed", label: "Speed", type: .number, default: .number(1), min: 1, max: 3, step: 1),
            ]),
        files: ["index.html": page(soft: 1, script: #"""
        const LOOP = 24, LINES = 18, SEGMENTS = 260;
        function draw() {
          const p = splash.params, w = canvas.width, h = canvas.height;
          const angle = TAU * p.speed * splash.time / LOOP;
          ctx.globalCompositeOperation = "source-over";
          ctx.fillStyle = p.background;
          ctx.fillRect(0, 0, w, h);
          ctx.globalCompositeOperation = "lighter";
          ctx.lineWidth = Math.max(1, h * 0.0028);
          for (let j = 0; j < LINES; j++) {
            const f = j / (LINES - 1);
            ctx.beginPath();
            for (let k = 0; k <= SEGMENTS; k++) {
              const u = k / SEGMENTS;
              const y = h * (0.25 + 0.5 * f) + h * 0.12 * Math.sin(u * TAU * 1.44 + angle + j * 0.35) + h * 0.05 * Math.sin(u * TAU * 3.6 - angle * 2 + j * 0.2);
              if (k === 0) ctx.moveTo(0, y); else ctx.lineTo(u * w, y);
            }
            ctx.strokeStyle = mix(p.colorA, p.colorB, f).replace("rgb", "rgba").replace(")", ",0.5)");
            ctx.stroke();
          }
          requestAnimationFrame(draw);
        }
        requestAnimationFrame(draw);
        """#)]
    )

    /// The lightest kind of scene: drawn once, applied as the real wallpaper, no process.
    static let dusk = Preset(
        id: "dusk",
        summary: "A still gradient with a low sun glow. Costs nothing once applied.",
        manifest: SceneManifest(
            id: "dusk", name: "Dusk", description: "A still gradient with a low sun glow. Costs nothing once applied.",
            tiers: [.static], fps: 1,
            params: [
                SceneParam(key: "top", label: "Sky", type: .color, default: .string("#1b1b3a")),
                SceneParam(key: "bottom", label: "Horizon", type: .color, default: .string("#e8806a")),
                SceneParam(key: "glow", label: "Glow", type: .color, default: .string("#ffd29a")),
                SceneParam(key: "height", label: "Glow height", type: .number, default: .number(0.78), min: 0.3, max: 0.95, step: 0.01),
            ]),
        files: ["index.html": page(soft: 1, script: #"""
        // No animation loop: the scene is drawn when it loads and when a parameter changes.
        function draw(p) {
          const w = canvas.width, h = canvas.height;
          const sky = ctx.createLinearGradient(0, 0, 0, h);
          sky.addColorStop(0, p.top);
          sky.addColorStop(1, p.bottom);
          ctx.fillStyle = sky;
          ctx.fillRect(0, 0, w, h);
          const glow = ctx.createRadialGradient(w / 2, h * p.height, 0, w / 2, h * p.height, h * 0.6);
          glow.addColorStop(0, p.glow + "ee");
          glow.addColorStop(1, p.glow + "00");
          ctx.fillStyle = glow;
          ctx.fillRect(0, 0, w, h);
        }
        window.addEventListener("resize", () => draw(splash.params));
        splash.onParams(draw);
        """#)]
    )

    /// A starting point for an agent: a plain colour that asks to be changed.
    static let blank = Preset(
        id: "blank",
        summary: "A plain colour. A starting point for the AI.",
        manifest: SceneManifest(
            id: "blank", name: "Blank", description: "A plain colour. A starting point for the AI.",
            tiers: [.static], fps: 1,
            params: [SceneParam(key: "color", label: "Colour", type: .color, default: .string("#101018"))]),
        files: ["index.html": page(soft: 4, script: #"""
        function draw(p) {
          ctx.fillStyle = p.color;
          ctx.fillRect(0, 0, canvas.width, canvas.height);
        }
        window.addEventListener("resize", () => draw(splash.params));
        splash.onParams(draw);
        """#)]
    )
}

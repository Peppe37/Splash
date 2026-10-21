#!/usr/bin/env python3
"""Builds the live demos for the website from the bundled presets.

Each preset in registry/presets becomes site/scenes/<id>.html: the scene's own page with the real Splash SDK in front of it
(the JavaScript that SplashCore injects in the app), so the website shows what the app draws. It also writes site/scenes.json,
the list the page uses to build the preset switcher and the colour controls.

Run from the repository root:  python3 scripts/build_site.py
"""
import json
import pathlib
import re

root = pathlib.Path(__file__).resolve().parent.parent
presets = root / "registry" / "presets"
out = root / "site" / "scenes"
out.mkdir(parents=True, exist_ok=True)

swift = (root / "Sources" / "SplashCore" / "SceneRuntimeScript.swift").read_text()
match = re.search(r'static let body = #"""\n(.*?)\n\s*"""#', swift, re.S)
if not match:
    raise SystemExit("Could not find the SDK in SceneRuntimeScript.swift")
sdk = "\n".join(line[4:] if line.startswith("    ") else line for line in match.group(1).split("\n"))

order = ["gradient-drift", "aurora", "starfield", "waves", "ribbons", "dusk", "blank"]
folders = sorted(presets.iterdir(), key=lambda f: order.index(f.name) if f.name in order else len(order))
listing = []
for folder in folders:
    manifest_file = folder / "scene.json"
    if not manifest_file.exists():
        continue
    manifest = json.loads(manifest_file.read_text())
    html = (folder / manifest.get("entry", "index.html")).read_text()
    params = {p["key"]: p["default"] for p in manifest.get("params", [])}

    boot = "window.__splashBoot = %s;" % json.dumps(
        {"fps": min(manifest.get("fps", 30), 30), "params": params, "stillAfter": 0, "detail": 1.5}
    )
    # The page can send new parameter values, so the website's colour pickers change the scene.
    bridge = (
        "window.addEventListener('message', function (event) {\n"
        "  if (event.data && event.data.params) splash._setParams(Object.assign({}, splash.params, event.data.params));\n"
        "});"
    )
    script = "<script>\n%s\n%s\n%s\n</script>" % (boot, sdk, bridge)
    (out / ("%s.html" % manifest["id"])).write_text(html.replace("<body>", "<body>\n" + script, 1))

    listing.append({
        "id": manifest["id"],
        "name": manifest["name"],
        "summary": manifest.get("description", ""),
        "tiers": manifest.get("tiers", []),
        "animated": manifest.get("tiers") != ["static"],
        "params": [p for p in manifest.get("params", []) if p["type"] == "color"],
    })

(root / "site" / "scenes.json").write_text(json.dumps(listing, indent=2) + "\n")
print("wrote %d scenes" % len(listing))

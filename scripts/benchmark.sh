#!/bin/sh
# Measures the CPU and memory of the Splash runner while it shows a scene, so the figures in the README can be repeated.
#
# Usage: scripts/benchmark.sh <scene-folder> [seconds] [--loop]
#   <scene-folder>  a scene, for example registry/presets/waves
#   seconds         how long to sample (default 10)
#   --loop          measure the baked tier (records the loop first) instead of the live tier
#
# It uses the build in .build/debug (or the folder in SPLASH_BIN), a temporary data folder, and switches off "pause in Low Power
# Mode" while it runs (and puts your choice back), because a paused wallpaper costs nothing and would show nothing.
# The WebKit processes the runner starts are counted by comparing with the ones that already exist, so close other web views
# (a browser window is enough to spoil the numbers) before you run it. Decoding done by system daemons is not counted.
set -e

SCENE="${1:?Usage: scripts/benchmark.sh <scene-folder> [seconds] [--loop]}"
SECONDS_TO_SAMPLE="${2:-10}"
MODE="live"
for arg in "$@"; do [ "$arg" = "--loop" ] && MODE="loop"; done
BIN="${SPLASH_BIN:-.build/debug}"
[ -x "$BIN/splash-runner" ] || { echo "Build first: swift build (looked in $BIN)"; exit 1; }

DOMAIN="com.giuseppe.splash"
PREVIOUS="$(defaults read "$DOMAIN" pauseInLowPowerMode 2>/dev/null || echo unset)"
export SPLASH_HOME="$(mktemp -d)"
RUNNER_PID=""
cleanup() {
  if [ -n "$RUNNER_PID" ]; then kill "$RUNNER_PID" 2>/dev/null || true; wait "$RUNNER_PID" 2>/dev/null || true; fi
  if [ "$PREVIOUS" = unset ]; then defaults delete "$DOMAIN" pauseInLowPowerMode 2>/dev/null || true
  else defaults write "$DOMAIN" pauseInLowPowerMode -bool "$( [ "$PREVIOUS" = 1 ] && echo true || echo false )"; fi
  rm -rf "$SPLASH_HOME"
}
trap cleanup EXIT
defaults write "$DOMAIN" pauseInLowPowerMode -bool false

sample() { # prints "pid command cpu mem" lines of the second top sample for the runner and WebKit helpers
  top -l 2 -s "$1" -stats pid,command,cpu,mem -o cpu -n 60 2>/dev/null | awk '/^PID/{n++} n==2' | grep -E "splash-runner|WebKit"
}

echo "Baseline (no runner)..."
BASELINE="$(sample 3 || true)"

if [ "$MODE" = loop ]; then
  echo "Recording one loop of ${SCENE}..."
  "$BIN/splash" bake "$SCENE" "$SPLASH_HOME/loop.mov" --width 1280 --height 800 --fps 30 >/dev/null
  ABS_SCENE="$(cd "$SCENE" && pwd)"
  printf '{"sceneDirectory":"%s","tier":"baked","mediaPath":"%s"}\n' "$ABS_SCENE" "$SPLASH_HOME/loop.mov" > "$SPLASH_HOME/state.json"
  "$BIN/splash-runner" &
else
  "$BIN/splash-runner" "$SCENE" &
fi
RUNNER_PID=$!
sleep 4   # let it settle

echo "Sampling for ${SECONDS_TO_SAMPLE} seconds (${MODE})..."
AFTER="$(sample "$SECONDS_TO_SAMPLE" || true)"

python3 - "$MODE" <<PY
import re, sys
def mb(text):
    m = re.match(r"([\d.]+)([KMG]?)", text)
    if not m: return 0.0
    n, unit = float(m.group(1)), m.group(2)
    return n / 1024 if unit == "K" else n * 1024 if unit == "G" else n
def rows(block):
    out = []
    for line in block.strip().splitlines():
        parts = line.split()
        if len(parts) >= 4: out.append((parts[0], " ".join(parts[1:-2]), float(parts[-2]), mb(parts[-1])))
    return out
base = """$BASELINE"""
after = """$AFTER"""
b = [r for r in rows(base) if "WebKit" in r[1]]
a = rows(after)
runner = [r for r in a if "splash-runner" in r[1]]
base_pids = {r[0] for r in b}
web = [r for r in a if "WebKit" in r[1] and r[0] not in base_pids]
rc, rm = sum(r[2] for r in runner), sum(r[3] for r in runner)
wc, wm = sum(r[2] for r in web), sum(r[3] for r in web)
print()
print("%-26s %8s %10s" % ("", "CPU %", "Memory MB"))
print("%-26s %8.1f %10.1f" % ("splash-runner", rc, rm))
print("%-26s %8.1f %10.1f   (%d new process%s)" % ("WebKit helpers it started", wc, wm, len(web), "" if len(web) == 1 else "es"))
print("%-26s %8.1f %10.1f" % ("total", rc + wc, rm + wm))
PY

# Performance

Being light is the main feature. A wallpaper is on all day, on laptops, next to the user's real work. This page is the contract.

## Budgets (targets)

| Situation | Target |
| --- | --- |
| Static tier applied | 0 processes, 0% CPU |
| Baked tier playing | Runner under 30 MB, no web process |
| Live tier, 30 fps, simple scene | Under 10% of one core in total on Apple silicon |
| Window covered, screen asleep or locked | Renderer destroyed, runner idle at 0% CPU |
| Editor closed | Only the runner exists |

## Measured

One MacBook Pro (Apple silicon, macOS 26.6), debug build, sampled with `top` over 4 seconds, Low Power Mode pause switched off for the test. Not a benchmark: one machine, one run per case, and decoding done by system daemons (`mediaplaybackd`, the GPU) is not counted.

| Case | Runner | Web processes | Total |
| --- | --- | --- | --- |
| Live, `waves` at 30 fps | 1.6% CPU, 19 MB | 2 processes, about 5% CPU, 150 MB | about 6.6% CPU, about 170 MB |
| Baked, `aurora` loop | 0.9% CPU, 14 MB | none | 0.9% CPU, 14 MB |
| Paused (Low Power Mode) | 0% CPU, 50 to 70 MB with a still frame held | | |

This is why the baked tier is the default for scenes that loop: about a tenth of the memory and no web processes. A release-build measurement and a CI benchmark are still to do.

## Rules

1. **Two processes.** The editor (heavy, temporary) and the runner (tiny, permanent) are separate. Applying a scene hands over to the runner; the editor can quit.
2. **Lightest tier first.** Static, then baked, then live. A scene opts into live only if it has to.
3. **One decision point.** `PerformancePolicy.decide` is the only code that decides run, pause or suspend. It is pure and unit tested.
4. **Events, not timers.** The runner reacts to system notifications (thermal, Low Power Mode, power source, sleep, lock, occlusion). No polling loop, no repeating timer.
5. **Suspend frees memory.** When the window is covered or the screen sleeps, the web view is destroyed, not just paused.
6. **A pause shows a picture.** Pausing a scene that has not drawn yet draws three frames and stops, so the desktop is never black.
7. **Frame cap enforced centrally.** `requestAnimationFrame` is replaced, so a scene cannot draw faster than allowed. Default 30 fps; 15 on battery; 24 under fair thermal pressure; paused when serious.
8. **Low Power Mode pauses** by default. Pausing on battery and the battery frame rate are settings (Splash > Settings).
9. **No hidden work.** No telemetry, no update polling in the runner, no network unless the scene declares it.
10. **Scenes are cheap by construction.** The linter warns about high fps. The agent rules tell AI to draw small canvases scaled up and to avoid work while nothing changes.

## Choosing a tier

- Does it move? If not, `static`.
- Does it move in a loop and need no input? `baked`.
- Does it react to audio, the mouse or live data? `live`.
- Does it change slowly (time of day, weather)? `static`, regenerated on a schedule.

## Measuring

`splash doctor` shows the state the policy sees. A benchmark target is planned: run the runner with a preset, sample CPU and resident memory over a few minutes, fail the build if a budget is exceeded.

import Foundation

/// The JavaScript SDK that the runner and the editor inject into every web scene before its own code runs.
/// It caps `requestAnimationFrame` at the frame rate chosen by `PerformancePolicy`, so a scene never
/// draws faster than the system allows, and it gives scenes their parameters.
public enum SceneRuntimeScript {
    /// Script to inject at document start. `params` is the JSON object of current parameter values.
    /// With `startPaused` the scene draws a few frames and then stops, so a paused wallpaper shows a still picture, not a black screen.
    ///
    /// `detail` is how much of the screen's real resolution a scene should draw: 1 is every device pixel (used when recording
    /// or taking a picture, where quality is free), 2 is half (used for a live wallpaper, where every pixel costs power).
    public static func source(fps: Int, paramsJSON: String, startPaused: Bool = false, detail: Double = 2) -> String {
        """
        window.__splashBoot = { fps: \(fps), params: \(paramsJSON), stillAfter: \(startPaused ? 3 : 0), detail: \(detail) };
        """ + body
    }

    /// Encodes the default values of a manifest as a JSON object string.
    public static func defaultParamsJSON(for manifest: SceneManifest) -> String {
        var values: [String: JSONValue] = [:]
        for param in manifest.params { values[param.key] = param.default }
        guard let data = try? JSONEncoder().encode(values), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    static let body = #"""
    (function () {
      var boot = window.__splashBoot;
      var nativeRAF = window.requestAnimationFrame.bind(window);
      var nativeCancel = window.cancelAnimationFrame.bind(window);
      var fps = boot.fps, interval = 1000 / fps, last = 0, paused = false, scheduled = false, nextId = 1;
      var queue = new Map();
      var paramListeners = [], pauseListeners = [];

      function loop(now) {
        scheduled = false;
        if (paused) return;
        if (now - last >= interval - 2) {
          last = now;
          var batch = Array.from(queue.entries());
          queue.clear();
          batch.forEach(function (entry) { entry[1](now); });
          if (boot.stillAfter > 0 && --boot.stillAfter === 0) { window.splash._pause(); return; }
        }
        if (queue.size > 0) schedule();
      }
      function schedule() {
        if (!scheduled && !paused) { scheduled = true; nativeRAF(loop); }
      }
      window.requestAnimationFrame = function (callback) {
        var id = nextId++;
        queue.set(id, callback);
        schedule();
        return id;
      };
      window.cancelAnimationFrame = function (id) { queue.delete(id); };

      var started = performance.now(), virtualTime = null;
      window.splash = {
        params: boot.params,
        get fps() { return fps; },
        /** Resolution divisor the host asks for: canvas pixels = device pixels / detail. */
        get detail() { return boot.detail; },
        get paused() { return paused; },
        /** Seconds since the scene started, not counting time spent paused. */
        get time() { return virtualTime !== null ? virtualTime : (performance.now() - started) / 1000; },
        /** Called with the new values whenever the user changes a parameter. */
        onParams: function (callback) { paramListeners.push(callback); callback(window.splash.params); },
        onPause: function (callback) { pauseListeners.push(callback); },
        _setParams: function (values) {
          window.splash.params = values;
          paramListeners.forEach(function (callback) { callback(values); });
        },
        _setFPS: function (value) { fps = value; interval = 1000 / value; },
        /** Used by the baker: fixes the clock at t seconds, then runs one frame now. */
        _renderAt: function (t) {
          virtualTime = t;
          var batch = Array.from(queue.entries());
          queue.clear();
          batch.forEach(function (entry) { entry[1](performance.now()); });
        },
        _pause: function () {
          if (paused) return;
          paused = true;
          pauseListeners.forEach(function (callback) { callback(true); });
        },
        _resume: function () {
          if (!paused) return;
          paused = false;
          pauseListeners.forEach(function (callback) { callback(false); });
          schedule();
        }
      };
    })();
    """#
}

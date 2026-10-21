# AI agents

Splash does not call an AI API and never asks for an API key. To use AI, the user installs an agent CLI they already use and are signed in to. Splash runs it as a subprocess, with the scene folder as its working directory.

## Status

| Agent | State | Notes |
| --- | --- | --- |
| Claude Code | **Works, tested** | `claude -p <prompt> --output-format stream-json --verbose --permission-mode acceptEdits --allowedTools Read,Edit,Write,Glob,Grep,Bash(<splash>:*)`. Tested end to end: it edited the scene and ran the linter. |
| Codex | Wired up, **not tested** | `codex exec --sandbox workspace-write --skip-git-repo-check [--image <png>] <prompt>`. Codex is not installed on the development machine; these flags come from memory and must be checked. |
| OpenCode | **Switched off** | `opencode run <prompt> --auto --standalone [--file <png>]`. In two test runs it edited `registry/presets/blank` in the Splash repository instead of the scene copy in another folder, even though the process was started in the scene folder. `opencode run` has no option for a working directory, and the cause was not found. Set `SPLASH_ENABLE_OPENCODE=1` to try it on a scene you can afford to lose. |

The flags of each tool change often. Check them against the tool's current `--help` before relying on them.

## How a turn works

1. The user types a request, or draws and pins comments on the preview and types a request.
2. The editor saves a snapshot of the scene folder, so the whole turn can be undone.
3. If there are drawings, the editor composes a frame of the preview with the drawings and numbered pins into a PNG in `.splash/annotations/` inside the scene folder.
4. `AgentRequest` builds the prompt: the request, the image path, the comments (`x`, `y` as fractions of the frame, and the scene time), the rule to touch only the working directory, and the full path of the `splash` tool for linting.
5. `AgentSession` starts the agent with the scene folder as working directory, standard input closed, and streams its output. For Claude Code the JSON events become chat lines: what it said, and what it did ("Edit index.html").
6. While files change, the preview reloads, at most once a second.
7. When the agent ends, the editor reloads the scene from disk (the agent may have changed `scene.json`) and runs the linter. Problems are shown in the chat.
8. The user keeps the result or restores the previous version from the History tab. Nothing is applied to the desktop until the user presses Apply.

The same engine is available from the terminal: `splash ask <scene> "<request>" [--agent claude]`.

## What the agent knows

Every scene folder has an `AGENTS.md` (and a `CLAUDE.md` that imports it) with the rules and the SDK. The repository also ships a skill in [`skills/splash/`](../skills/splash/SKILL.md), following the approach of [HyperFrames](https://github.com/heygen-com/hyperframes): a skill that tells an agent how to make a scene. It is not packaged for installation into the agents yet. The agent can check its own work with `splash lint` and `splash snapshot`.

## Safety

- The agent runs with the **user's own login and permissions**. Splash does not sandbox it. Claude Code is limited by `--allowedTools` to reading and editing files and running the `splash` tool, and its working directory is the scene folder; Codex is started with its workspace-write sandbox.
- Every prompt tells the agent to touch only the working directory. That is an instruction, not a guarantee, as the OpenCode result shows. A change outside the scene is not covered by the History tab.
- The editor shows what the agent does and never applies a scene by itself.
- Scene code the agent writes is untrusted when it runs: no network, no persistent storage, unless the manifest asks for it and the user allows it.
- Prompts and images sent to an agent leave the machine, as with any use of that agent.

## Later

[Agent Client Protocol](https://agentclientprotocol.com) could replace the per-CLI adapters with one. Not evaluated yet.

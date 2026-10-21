# Security Policy

## Reporting a vulnerability

Please **do not open a public issue** for a security problem.

Report it privately with GitHub's private vulnerability reporting (Security tab of the repository, then "Report a vulnerability"). Include what you found, how to reproduce it, and the version of Splash and macOS.

This is a one-person, free project in pre-alpha, so please allow a few days for an answer.

## What is in scope

- **Scene sandboxing.** Scene code is untrusted. Anything that lets a scene read files outside its folder, reach the network without `permissions.network`, keep data between runs, or run native code is a vulnerability.
- **The agent bridge**: how the editor starts agent CLIs and passes them prompts, images and file paths, and anything that lets an agent change files outside the scene folder.
- **Scene packages** (`.splashscene`): unpacking and installing, including path traversal and permission review.
- The release workflows, the signing certificate and the in-app updater: it only downloads from this repository's releases, and refuses an update that is not signed with the same identity as the running app.

## Supported versions

Only the latest release receives fixes. There is no release yet.

## Good to know

- Splash has no analytics and no telemetry, and the runner makes no network calls of its own. The editor asks GitHub once a day, while it is open, for the list of releases (it can be switched off in Settings → About).
- Splash never asks for an AI API key. AI features run the user's own agent CLI, with that CLI's own permissions. Prompts sent to it leave the machine like any other use of it.

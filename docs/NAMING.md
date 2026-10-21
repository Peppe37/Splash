# Naming

The app is called **Splash**. (It was called Cromio while it was being planned; Deskolino, Sfondino and Procedino were also considered.)

## What is called what

| Thing | Name |
| --- | --- |
| App | Splash |
| Wallpaper process | Splash Runner (`splash-runner`) |
| Command line tool | `splash` (inside the app bundle: `splash-cli`, because `splash` and `Splash` are the same file name on a case-insensitive disk) |
| Swift modules | `SplashCore`, `SplashPlatform` |
| Scene package | `.splashscene` |
| Bundle ids | `com.giuseppe.splash.editor`, `com.giuseppe.splash.runner` |
| Data folder | `~/Library/Application Support/Splash` (override: `SPLASH_HOME`) |
| JavaScript object in scenes | `splash` (`splash.params`, `splash.time`) |

## Known risk

"Splash" is a common word and other software uses it (for example Splash, the JavaScript rendering service, and SplashKit). Before a wider release, check the app stores and trademark databases for the name.

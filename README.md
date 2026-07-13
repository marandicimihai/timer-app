# Minimal Timer

A local-only macOS menu-bar activity tracker with a Pomodoro timer. Activity
logs are stored in `~/Library/Application Support/MinimalTimer/activity-history.sqlite`.

## Run

Open `Package.swift` in Xcode 16 or later and run the `MinimalTimer` scheme, or run:

```sh
swift run MinimalTimer
```

The app requires macOS 14 or later. Data remains on this Mac only.

## Install

Install a signed release build in your personal Applications folder:

```sh
./scripts/install.sh
open "$HOME/Applications/Minimal Timer.app"
```

The installed app runs only in the menu bar. It does not add a Dock icon.

## Test

```sh
swift test
```

The unit and menu-flow tests cover activity persistence, daily totals, history clearing,
Pomodoro phases, and the activity/Pomodoro interaction rules.

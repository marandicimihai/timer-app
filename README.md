# Minimal Timer

A local-only macOS menu-bar activity tracker with a Pomodoro timer. Activity
logs are stored in `~/Library/Application Support/MinimalTimer/activity-history.sqlite`.

## Run

Open `Package.swift` in Xcode 16 or later and run the `MinimalTimer` scheme, or run:

```sh
swift run MinimalTimer
```

The app requires macOS 14 or later. Data remains on this Mac only.

## Test

```sh
swift test
```

The unit and menu-flow tests cover activity persistence, daily totals, history clearing,
Pomodoro phases, and the activity/Pomodoro interaction rules.

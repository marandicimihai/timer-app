<p align="center">
  <img src="Design/minimal-timer-logo-lockup-v1.png" width="620" alt="Minimal Timer logo: a timer and check mark" />
</p>

# Minimal Timer

**A tiny macOS menu-bar timer for doing one thing at a time.**

Minimal Timer keeps activity tracking and Pomodoro sessions pleasantly out of
your way. Name what you are doing, start the clock, and get back to it. When
you are done, finish the activity and let the app keep the total. No accounts,
no subscriptions, no surprise upgrade screen—just a small timer that lives
where you already look.

## Why it feels good to use

- **One click away.** It lives in the menu bar, not in another busy window.
- **Activities without admin.** Start “Writing,” “Email,” or “Deep work”; the
  elapsed time is visible at a glance. Switch tasks or finish when you are
  ready.
- **A Pomodoro timer that does not make a scene.** Start a focus or break
  session, see its progress, and receive a notification when it ends.
- **A little history, not a dashboard.** Review completed activities and daily
  totals when you need a reality check. Delete individual entries or clear the
  history whenever you like.
- **Your defaults, your way.** Adjust focus and break lengths, toggle
  notifications, and choose which timer details appear in the menu bar.
- **Private by default.** Activity history stays on this Mac. Nothing is sent
  anywhere.
- **Actually free.** No fees, trials, ads, or artificial limits.

## Install

### The quick route

You need **macOS 14 or later** and **Xcode 16+** (or the Xcode Command Line
Tools).

1. Download or clone this project, then open **Terminal**.
2. Move into the project folder:

   ```sh
   cd /path/to/timer-app
   ```

3. Build and install it:

   ```sh
   ./scripts/install.sh
   ```

4. Open **Minimal Timer** from your personal `Applications` folder. You will
   find its timer icon in the menu bar—there is intentionally no Dock icon.

That is it. Click the menu-bar icon, type an activity, and press **Start
Activity**. For a focus session, use **Start Focus** in the same popover.

### Run it from Xcode instead

Open [`Package.swift`](Package.swift) in Xcode and run the `MinimalTimer`
scheme, or use:

```sh
swift run MinimalTimer
```

## A small tour

| When you want to… | Do this |
| --- | --- |
| Track a task | Enter its name and choose **Start Activity**. |
| Move to the next task | Enter the next name and choose **Switch Activity**. |
| Reuse something familiar | Choose it from **Recent**. |
| Take a focused break from multitasking | Choose **Start Focus**. When it completes, start the suggested break (or the next focus session). |
| See where the day went | Open **History** for daily totals and completed activities. |
| Tune the timer | Open **Settings** to change durations, alerts, and menu-bar display. |

## Your data

Minimal Timer stores completed activity history locally at
`~/Library/Application Support/MinimalTimer/activity-history.sqlite`. It stays
on your Mac; clearing history from the app removes those recorded activities.

## For contributors

Run the test suite with:

```sh
swift test
```

The tests cover activity history, Pomodoro behavior, settings, notifications,
and the menu-bar flow.

# Performance notes

Changes made on 2026-11-08 to remove typing and tap lag. Keep these rules when
adding features.

## Rules

- **Don't compute models in `body` over the whole history.** Wrap them with the
  screen's `memo("key") { … }` helper (Today, Trends, Analysis), which goes
  through `DerivedCache`. Results are reused until a SwiftData save or a change
  to the standard `UserDefaults` clears the cache. If a result depends on
  something else (a `@State` value, an app-group setting), put it in the key.
- **Keep fast-changing values out of big screens.** The recovery count-up lives
  in `RevealingScoreRing` and the "workout in progress" banner in
  `ActiveWorkoutBanner`, so neither redraws all of Today.
- **No disk writes or heavy work per keystroke.** Workout edits are coalesced
  (`WorkoutRecorder.persist`, 350 ms) and flushed when the app backgrounds, on
  lock-screen actions and when a session ends. The draft database uses WAL with
  `synchronous=NORMAL`, which survives the app being killed or crashing.
- **Tab switches must not redraw other tabs.** `TabNavigator` is always
  equal to itself (it carries only actions), so switching tabs doesn't redraw
  Today. Trends, Analysis and Insights use `LazyVStack` pages, so a tab's first
  open only builds the cards on screen. The tab-switch haptic is cheap and
  isn't a cause of lag.
- **Search off the main thread.** `SwissFoodDatabase` and
  `PolishProductDatabase` are `nonisolated`; the food search screen runs them in
  a detached task.
- **Buttons don't wait for Health refreshes.** Weigh-in saves update the list
  immediately and ask `HealthSync.refreshSoon(days:)` for a background refresh.
- **The minute refresh does as little as possible.** The sleep baseline is only
  relearned when data or day tags changed, and settings are only written when
  their value changed (every write clears `DerivedCache`).

## Checks run

- Tab switching (2026-11-08, Release build in the simulator, sampled with
  `sample`): about 70 ms of main-thread work the first time a tab opens and
  close to nothing after that.

- Debug and Release simulator builds succeed.
- `DiagnosticsTests/check_workout_lockscreen.py`, `run_food_chat_checks.py`,
  `check_ai_timeout.py` and `WorkoutDraftChecks.swift` pass.
- Today, Trends, Analysis and Weight render correctly with `-seedLocal`.
- Fuzzy food search costs ~60 ms per keystroke on a Mac (13,300 foods); it now
  runs in the background instead of blocking typing.

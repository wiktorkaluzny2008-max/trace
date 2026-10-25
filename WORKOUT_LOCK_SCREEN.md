# Workout set tracking from the Lock Screen

Start a workout in Trace as usual, then use its workout Live Activity on the Lock
Screen or expanded Dynamic Island. It shows the next unfinished **working** set,
its entered values (or the same coach/previous-session hints used in the app),
working-set progress, elapsed time and rest countdown.

- **Complete set** records that set through `WorkoutRecorder.toggleSet`, including
  its normal hint acceptance, completion timestamp and existing RIR behavior,
  then starts the exercise's rest timer/notification.
- **Undo** unchecks only the latest completed working set and cancels its rest.
- First-time sets without the required weight/reps or duration prompt for entry
  in Trace; their completion button is disabled. Edit quantities and RIR in the
  main app. This interface does not invent workout measurements.
- Warmups remain available in the app but do not inflate working-set progress.
- Session, exercise and set IDs guard stale/repeated taps. Completing an already
  completed set is a no-op, not a toggle. Old undo buttons cannot cancel later rest.
- Completing the last set does not finish/save the entire workout automatically;
  review and finish it in Trace.

`UpdateWorkoutSetIntent` conforms to `LiveActivityIntent`, so Apple executes it in
Trace's app process without intentionally opening the app UI. The same definition
is compiled into both targets. `TRACE_WIDGET_EXTENSION` isolates the extension's
non-executing fallback; the app owns and persists the active draft. No new shared
workout database or network sync is introduced. ActivityKit updates are serialized
and awaited before the intent finishes, and the rest deadline is restored with a
saved draft after process recreation. New Activity ContentState fields are optional
so older activity payloads still decode.

Apple's [interactive widgets documentation](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
explains app-process dispatch and notes that Lock Screen controls may require the
person to authenticate. This feature does not bypass device security. Only an
on-device test confirms behavior on a particular iPhone/iOS version.

## Validation (2026-10-05)

- Full Debug Simulator app + widget extension build succeeded without warnings.
- `python3 DiagnosticsTests/check_workout_lockscreen.py` passed. It compiles the
  production set-action/hint/persistence logic in a host harness with no-op UI and
  notification adapters. Checks cover session/set IDs, warmups, ordering, hint
  acceptance, duplicate taps, undo, rest invocation, saved draft data, missing
  values and all three tracking modes. It also compares the app/widget schemas
  and intent definitions for drift. It does not simulate WidgetKit intent dispatch.
- Physical Lock Screen interaction remains to be verified: start a routine with
  values/hints, lock the phone, complete a set, inspect rest and progress, then
  undo. Reopen Trace to confirm the matching checkbox and recorded values.

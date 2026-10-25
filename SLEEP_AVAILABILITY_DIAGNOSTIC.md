# Trace: overnight sleep-availability experiment

This is a read-only, opt-in diagnostic. It does not create alarms, change sleep
scores, write to HealthKit, send data to AI, or upload diagnostic logs.

## Test tonight

1. Build/run Trace on the paired **physical iPhone**, preserving the installed app
   and its data. Go to **Settings → Diagnostics → Sleep data availability**.
2. Tap **Start overnight experiment**. Allow **Sleep** read access if requested.
   Wait for **Initial baseline: Captured** and **Immediate delivery registered**.
   Inspect any error/events before relying on the experiment. A successful empty
   read cannot tell us whether read permission was denied. Check Trace's Sleep
   permission in Health if recent known sleep is absent (try all sources too).
3. Leave this experiment running across the whole night. Wear the Apple Watch
   with its normal sleep-tracking settings and adequate charge; keep the paired
   phone nearby, connected normally. Disconnect the debugger, launch Trace once
   from the phone, then leave it in the background and lock the phone normally.
   **Do not swipe Trace away.** Keep your usual independent wake-up alarm.
4. Tomorrow reopen that screen. Set **Night ending** to tomorrow's date. Look at
   the receipt times, Background counts, source details and events **before**
   your wake/unlock time. Foreground catch-up is deliberately labelled.
5. Repeat for several ordinary nights, recording your actual wake time and any
   overnight phone unlocks separately. Tap **Stop monitoring** after testing;
   the results remain available, and another start creates a separate run.

Background server queries cannot be tested in the Simulator. No promise of
real-time or guaranteed overnight execution is made.

## Implementation and data

- `SleepDiagnosticModels.swift`: raw sample/event/run records and pure summary
  helpers. Legacy `asleep` and `asleepUnspecified` share value 1; raw unknown
  category values are preserved. `inBed` and `awake` are shown but not counted as
  asleep in summaries.
- `SleepAvailabilityMonitor.swift`: uses Trace's existing `HKHealthStore`.
  `SleepDiagnosticAppDelegate` restores the observer in
  `application(_:didFinishLaunchingWithOptions:)`, before onboarding/aggregation.
  This includes system background launches after ordinary termination.
- A retained `HKObserverQuery` watches sleep additions/deletions. An opt-in
  `.immediate` background-delivery request is made and its outcome recorded.
  Each notification triggers a one-shot `HKAnchoredObjectQuery`. Calls serialize;
  a callback arriving during a read waits for a follow-up read. Every observer
  completion is called after its read has finished or failed. A 20-second
  timeout stops a stuck query if the process is executing; it is not a promise
  of background runtime. There is no polling timer or BGTaskScheduler job.
- Foreground entry, process launch, protected-data availability and **Check now**
  also read changes. The trigger is stored so these cannot masquerade as timed
  observer delivery. Observer arrival and read result/error events are separate.
- Initial history covers seven days and is explicitly marked baseline. The
  predicate's lower bound stays fixed for each persisted anchor. Old backfills,
  the initial baseline, deleted samples and negative latencies are excluded from
  summaries. A first empty read is still a baseline, not proof of read permission.
- Sample UUIDs deduplicate results within each experiment; the first-observed
  timestamp never changes. Deletions mark retained records instead of removing
  evidence. New replacement UUIDs are separate records. Each record includes raw
  category, start/end, first observed, source name/bundle/product/device,
  trigger, processing app state and protected-data availability. Event records
  also include Low Power Mode and background-refresh status at query start.
- Receipt time is captured in the HealthKit result callback before dispatch to
  the main actor; app state is captured when processing it. Thus **observed
  latency = first successful diagnostic read − sample end**, an upper bound on
  accessibility, not a timestamp supplied by HealthKit. We cannot separate Watch
  classification delay, Watch→iPhone sync, iOS scheduling and read-lock delay.
- Storage: app sandbox `Library/Application Support/SleepAvailability/observations.json`.
  One atomic write saves samples, events and securely archived query anchor
  together; a failed save does not advance the cursor. JSON schema versions and
  unreadable files are not silently reset. The directory is excluded from backup.
  Files use `completeUntilFirstUserAuthentication` so this local experiment can
  log while locked after first unlock. This does not bypass HealthKit protection.
  The app has no network/export pathway for these records. Uninstalling Trace
  removes them; ordinary termination does not. No SwiftData migration is needed.
- `SleepAvailabilityView.swift`: run/date/source selection, complete sample
  details, mean/median/max, 1/5/10/15/30-minute percentages and latest 100 events.
  All events remain on disk. The night window is 18:00–12:00 in the current local
  time zone; it is deliberately independent of Trace's existing night scoring.

## Interpreting results

Statistics are **per eligible asleep sample**, not time-weighted and not combined
sleep duration. The default Watch filter uses available product/device metadata;
turn it off if the source doesn't provide recognizable Watch metadata.

“Received during later sleep” means that the receipt falls within a different,
non-deleted **same-source** asleep interval recorded retrospectively. This is
stronger than “before the final sample ended”, but is not direct evidence that
we knew the user was asleep at receipt time. Awake gaps don't qualify. Missing
future samples or deletions can change this retrospective count. A zero means
no evidence, not proof the person was awake.

Promising result: repeated background reads with short latency (for example,
most within five minutes, with no long blind periods near the intended wake
window), while locked and asleep, across several nights. Inspect the raw
intervals and sources for coverage and revisions; a good median alone is not
enough. Final stages must also reach Trace in time near the desired sleep target.

If samples first appear as a morning batch, after unlocking or opening Trace,
or frequent failures/gaps exceed the acceptable alarm tolerance, this iPhone
HealthKit approach is not sufficient for an adaptive actual-sleep alarm. Even a
successful experiment establishes device-specific feasibility, not a system
reliability guarantee. A later design would still need a separately guaranteed
latest-wake fallback. **No adaptive alarm has been implemented.**

## Apple documentation checked (2026-09-29)

- [Sleep analysis categories](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis):
  in-bed intervals overlap stages; Watch awake samples can omit boundaries.
- [Sleep analysis type](https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier/sleepanalysis)
  and [WWDC22 sleep stages](https://developer.apple.com/videos/play/wwdc2022/10005/):
  stages are represented by category samples. These sources provide no bound for
  availability to an iPhone during an ongoing night's sleep.
- [Observer queries](https://developer.apple.com/documentation/healthkit/executing-observer-queries):
  notification does not carry samples; register observers at app-delegate launch;
  device testing is required.
- [Background delivery](https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery(for:frequency:withcompletion:))
  and [completion handler](https://developer.apple.com/documentation/healthkit/hkobserverquerycompletionhandler):
  acknowledge after handling; repeated failures to acknowledge cause backoff and
  can stop deliveries. `.immediate` is a requested delivery frequency, not a
  deadline for Watch classification/sync or successful reads.
- [Anchored queries](https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery):
  anchors retrieve subsequent additions/deletions; they are not an independent
  background wake mechanism.
- [Protecting privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy):
  a locked device encrypts the Health store, which may prevent background reads.
  Read-denied data appears absent; authorization completion is not proof of read
  access. The prototype records failures and retries when permitted.
- [About HealthKit](https://developer.apple.com/documentation/healthkit/about-the-healthkit-framework):
  iPhone and Watch each have their own store. Observer delivery is about the
  iPhone store, not a direct live sleep stream from the Watch.
- [iOS background limits, Apple DTS](https://developer.apple.com/forums/thread/685525):
  no general guaranteed periodic execution; force quitting normally blocks
  background relaunch until the user opens the app again. A BG refresh job would
  not provide a reliable minute-by-minute sampling schedule.

## Validation

Pure checks (no HealthKit writes or simulator seeding):

```sh
xcrun swiftc -module-cache-path /tmp/trace-sleep-swift-cache \
  RecoverySignal2/SleepDiagnostics/SleepDiagnosticModels.swift \
  DiagnosticsTests/SleepDiagnosticChecks.swift -o /tmp/trace-sleep-checks
/tmp/trace-sleep-checks
```

Checks cover empty/odd/even summaries, inclusive thresholds, historical/baseline/
deleted/negative-latency exclusions, category mapping, same-source retrospective
sleep evidence (including awake gaps and interval boundaries), and JSON/anchor
round-trip persistence. HealthKit background behavior requires tonight's physical
device experiment, not a unit test.

Validation completed on 2026-09-29: full Debug iOS Simulator build succeeded
with Xcode 27.0 (arm64, signing disabled), and all pure diagnostic checks passed.
No overnight iPhone result or real background-delivery claim has been established.
Even low latency after a stage ends does not reveal sleep within an unfinished
stage; inspect long gaps near the desired wake window as well as latency.

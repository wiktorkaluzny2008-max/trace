# RecoverySignal — setup

All the app's Swift code is already written in `RecoverySignal/` (the source
files, not a project yet). Once Xcode has finished installing, do this:

## 1. Create the Xcode project

1. Open Xcode → **File → New → Project**.
2. Choose **iOS → App**, click Next.
3. Product Name: `RecoverySignal`. Interface: **SwiftUI**. Language: **Swift**.
   Storage: leave "Host in CloudKit" unchecked (not needed).
4. Save it at `~/Desktop/RecoverySignal` — when it asks, **replace** the
   folder if prompted (or save one level up and merge — either way the goal
   is that the project ends up at `~/Desktop/RecoverySignal/RecoverySignal.xcodeproj`).
5. Xcode will create its own `RecoverySignalApp.swift`, `ContentView.swift`,
   and a preview asset catalog inside `RecoverySignal/RecoverySignal/`.
   **Delete the ones Xcode generated** (they'll conflict with the versions
   already sitting in that folder) — keep `Assets.xcassets` and the
   `Preview Content` folder.
6. Modern Xcode (16+) uses "file system synchronized groups" by default —
   any `.swift` file physically present in the `RecoverySignal/RecoverySignal/`
   folder is automatically part of the project, no manual "Add Files" step
   needed. If your Xcode version is older and the files under that folder
   *don't* show up in the project navigator, right-click the group in Xcode
   → **Add Files to "RecoverySignal"…** → select all the `.swift` files.

## 2. Add the HealthKit capability

1. Select the project in the navigator → the `RecoverySignal` target →
   **Signing & Capabilities** tab.
2. Under **Signing**, pick your Apple ID as the team (a free personal team
   is fine for installing to your own device).
3. Click **+ Capability** → add **HealthKit**. Leave the sub-options
   unchecked (we don't need clinical records or background delivery
   entitlements beyond the default).

## 3. Add Health usage description strings

Still in the target settings, open the **Info** tab and add these two rows
(right-click → Add Row):

- `Privacy - Health Share Usage Description` →
  "RecoverySignal reads your Watch and nutrition data to show trends and personalized insights."
- (Health Update Usage Description is **not** needed — this app never writes to Health.)

## 4. Run it

- **On a physical iPhone** (recommended — Simulator has no real Watch/Yazio
  data): plug in your iPhone, select it as the run destination, hit ▶️.
  On a free (non-paid) Apple ID, the app will need re-installing from Xcode
  roughly every 7 days — that's an Apple restriction on free provisioning,
  not a bug.
- First launch will prompt for Health access — grant read access to
  everything listed (HRV, heart rate, sleep, steps, energy, body mass,
  and the dietary nutrients).
- Make sure Yazio's **Settings → Apple Health** sync is turned on so its
  logged food shows up as nutrition data in Health for RecoverySignal to read.

## 5. Add your Anthropic API key

In the app's **Settings** tab, paste an API key from console.anthropic.com
to enable the "Generate weekly narrative" button on the Insights tab. This
is optional — the rule-based flags on the Insights tab work without it.

## What's already built

- `HealthKitManager.swift` — all HealthKit read queries (biomarkers + nutrition + sleep + workouts), plus background delivery so data refreshes without opening the app.
- `MetricsAggregator.swift` — turns raw HealthKit samples into daily rows stored locally (SwiftData).
- `InsightRules.swift` — deterministic threshold checks (recovery deficit, sleep debt, protein shortfall, body-weight trend). Tune the constants at the top as you learn your own baseline.
- `NarrativeService.swift` — sends only aggregated weekly stats to Claude to generate a plain-language weekly write-up.
- `TodayView` / `TrendsView` / `InsightsView` / `SettingsView` — the four tabs.

## Known gaps to revisit together once it's running

- The rule-engine thresholds (HRV drop %, protein target, sleep debt) are
  reasonable defaults, not calibrated to you specifically — expect to tune
  them after a couple of weeks of real data.
- Body composition framing is explicitly a *directional inference* from
  weight trend + intake + resistance-training frequency — it is not, and
  can't be, a real muscle-vs-fat measurement without a smart scale with
  bioimpedance (which *can* sync to Health if you get one later) or a
  DEXA scan.
- No onboarding flow yet for someone with zero data history — the empty
  states just say "no data yet," which is fine for you as the only user
  but worth knowing.

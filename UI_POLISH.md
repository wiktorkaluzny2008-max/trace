# Interface review — 25 September 2026

Implemented:
- Persistent section shortcuts in Trends and Analysis, with reduced-motion support.
- Compact navigation titles, distinct chart title/average/change hierarchy, and taller charts.
- Per-chart recorded-day counts (coverage only, not statistical confidence).
- Expandable chart reading guidance and clearer empty states.
- Stable date identities for daily chart points and date/series identities for stacked points.
- Clear chart selection on range changes; preserve each metric's colour on its latest bar.
- Exclude future/non-finite readings from the shared range filter.
- Food methods use three columns, or two with accessibility text sizes; meal selection still comes first.
- Expandable food source details with a concise visible duplicate-logging reminder.
- Polish translations for new interface text.

Validation: Simulator build passed. Regression checks passed for point identity across refreshes and distinct stacked series. Trends and Food screenshots inspected; the simulator has no recent health history. Populated charts, section shortcut taps and physical haptics still require device verification.

Potential next features (not implemented):
1. Recommendation audit trail: show contributing inputs, missing readings, and changes in advice over time. Coverage must not be presented as clinical confidence.
2. Comparable-session analysis: compare the same exercise at similar load/RIR against prior sleep and food logs, report paired observations and uncertainty, and avoid causal claims.
3. Logging reconciliation: flag likely duplicate meals and unmatched Health writes, with user review before changing records.

Competitor context: Oura already offers experiments (https://support.ouraring.com/hc/en-us/articles/19663280975379-Oura-Experiments); MacroFactor already offers adaptive expenditure (https://macrofactor.com/expenditure-v3/); Hevy already offers muscle distribution (https://help.hevyapp.com/hc/en-us/articles/35702030346903-Hevy-Statistics-Explained-Track-Your-Training-Progress-and-Muscle-Growth). The proposals above are differentiation opportunities, not verified exclusive features.


## Usability pass — 26 September 2026

- Kept the unified Today shortcut panel; its layout, greeting and recovery summary now adapt to accessibility text sizes.
- Moved routines and recent sessions ahead of optional workout guidance. Guidance remembers whether it is expanded. Routine menus have larger tap targets and last-performed dates no longer squeeze the set counts.
- Added search by workout/exercise name and source filters to workout history, grouped by month with explicit loading/empty states. Existing view/edit destinations remain available.
- Prioritised actual meal logs above recipe suggestions, added per-meal calorie totals, reduced vertical gaps, and added a close control for logging methods. Meal choices reflow at large text sizes.
- Added food search filters for all/reference/product/personal foods, cancellation-safe loading state, retry, clear offline availability, and interactive keyboard dismissal.
- Saved meals respect the selected meal slot. Copy/saved-meal logging now reports partial failures and denied nutrient writes rather than always playing a success haptic. Copy only considers earlier days.
- Protected nonempty meal baskets from accidental dismissal; blocked repeated logging and edits during a save; saved-meal creation errors are surfaced and retries do not create duplicate saved-meal presets.
- Simplified the bottom food total bar to calories and grams eaten, with responsive layouts, accessible macro names, and reduced-motion support. Chart range selectors and history/search source controls use menus at accessibility sizes.
- Added Polish text for the new controls and messages.

Validation: full simulator scheme (app + widget extension) compiled successfully. Inspected Today, Food, Workouts, search with bundled chicken results, and the Polish food-method screen at accessibility-medium text size. Restored the simulator's original text size. New localization keys and format placeholders were checked. Simulator history is empty; populated history filters, cancellation during a live request, physical haptics, and HealthKit success/failure flows have not been exercised end to end on a phone. No real health data was written as part of this pass.

Debug preview entry points: `-resetTodayNavigation` resets only the simulator/development navigation for a screen check; `-previewFoodMethods`, `-previewFoodSearch` and `-previewFoodQuery` allow deterministic food screen previews. These hooks compile only in Debug builds.

## Food diary dates — 2026-10-06

The food logger has a pinned date bar: swipe left for the next day, right for the
previous day, or use the labelled arrows and Today shortcut. The swipe is limited
to the date bar so food-row deletion and vertical scrolling keep their behavior.
The chosen date filters meals/totals and follows search/barcode amounts, manual
and text-AI baskets, photo/Gemini saves, pasted macros, copied meals and saved
meals. Editing retains the original entry timestamp unless explicitly changed.
Water/caffeine quick-add remains available on Today only.

Future days use local food totals when no DailyMetrics record exists; navigating
or logging tomorrow does not create future health-summary rows. Dates use calendar
arithmetic across daylight-saving transitions. Batch writes capture the chosen
 date and disable navigation until completion. Other scan/paste entry points retain
log-now behavior through an optional date environment value.

Validation: full Debug Simulator app/widget build succeeded; checks in
DiagnosticsTests/check_food_dates.swift passed for past/future days, year changes,
and 23/25-hour Zurich days. Real-device HealthKit writes for future entries and
swipe interaction still need an iPhone check.


## App-wide OLED/orange integration — 22 October 2026

Applied the Appllama-informed design to the actual SwiftUI app: Today, Train,
Trends, Analysis, Insights, all health details, Food, body logging, Settings and
Onboarding. The shared system uses black/charcoal surfaces, neutral symbols,
orange primary actions with dark ink, semantic data colours and Dynamic Type.
Body now leads with weight, Nutrition avoids a duplicate calorie hero, and food
meal targets adapt from two columns to one at accessibility text sizes.

Workout logging includes a bottom set editor, native value wheel with exact
entry, set-type sheet/right swipe, 30-second rest controls, foreground countdown
haptics and record feedback. Drafts migrate from UserDefaults to a synchronous
SQLite snapshot; failed local log saves retain the active session. The lock-screen
regression harness tests production action logic; WorkoutDraftChecks.swift tests
the independent storage implementation.

Debug simulator and Release iPhone builds passed. Sample workout editing,
relaunch/update restoration and local finish were verified. All major screens,
light mode, larger Food/Sleep text and onboarding were visually inspected.
Physical haptic feel, measured frame rate/cold-start budget and real Health/AI
service paths remain device checks. The existing phone installation launched
successfully; no redesigned build was installed on the phone.

Detailed tokens, haptics, research, screenshots and limitations:
`../Trace-Redesign-Review/Integration-Notes.txt`.

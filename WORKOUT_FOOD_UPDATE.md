# Workout history and food expansion — September 2026

Workouts now includes the five latest sessions and a clock shortcut to the full history. App sessions open with Edit: name, session/exercise notes, weights, reps or duration, RIR, completion, and set type. Edits use independent value drafts, so Cancel makes no changes. Save validates numeric ranges, explicitly saves SwiftData, and restores the original values if saving fails. Derived volume, working-set counts and future history-based suggestions read the amended sets. Dates, Watch sensor data and Apple Health workout records are not rewritten. Imported Watch sessions remain view-only.

Food catalogue: retained all 1,246 Swiss records; added named typical presets to 84. Added 5,413 FNDDS general foods with exact published macros and portion weights, bringing bundled USDA records to 12,077. See Food/FoodDataSources.md for provenance and the distinction between official nutrition data and approximate Swiss serving presets. Named servings use full-width choices; users can always switch to grams.

Validation: Simulator target builds; import audit compared every new nutrient and portion to the original USDA source, checked unique IDs and positive serving weights. Device interaction and Apple Health integration still require a physical-device check.

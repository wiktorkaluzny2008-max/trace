# Food sources and serving sizes

Swiss foods: all 1,246 records already bundled from the Swiss Food Composition Database, FSVO, version 7.1. https://valeursnutritives.ch/en/downloads/

General foods: existing USDA SR Legacy records plus 5413 records from USDA FNDDS 2021–2023 (October 2024 release). Public source: https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_survey_food_json_2024-10-31.zip

New general entries retain FDC IDs, published calories/macros per 100 g, and up to three exact named portion weights. Records with missing energy/protein/carbohydrate/fat, invalid values, or no useful portion are excluded. Unspecified and guideline portions are excluded. No calories or macros were invented or imputed. FNDDS dishes are generic recipe estimates, not guarantees for a particular restaurant or brand.

Swiss named portions are app-defined, approximate convenience weights (e.g. a 30 g raclette slice, 180 g yogurt pot), not FSVO serving recommendations. The interface labels them as typical weights and always permits weighed grams. Existing drink density conversion remains available.

## Everyday shortcuts and Polish localisation — 6 October 2026

32 additional everyday entries in CommonFoods.swift retain exact calories, protein, carbohydrate and fat from the bundled USDA SR Legacy record identified by referenceFDCID. They provide simpler English names, Polish translations and bilingual search aliases. Each offers three app-defined approximate edible serving weights; these are convenience portions, not USDA dietary recommendations. Users can always enter weighed grams.

## Polish-market Open Food Facts snapshot — 6 October 2026

PolishProducts.json contains 123 distinct Polish-market product records from Open Food Facts, including twaróg, serek wiejski and pierogi. This is community-contributed product-label data, not the licensed Polish national food-composition tables. Entries are labelled “Open Food Facts · product data” and do not receive a verified tick.

100 records include a serving explicitly stated in grams on the source label; the remaining records use weighed grams without an invented label portion. The import excludes incomplete/non-finite macro records, implausible macro totals and substantial energy inconsistencies. These checks are not independent nutritional verification. Liquid records were excluded from this snapshot to avoid treating millilitres as grams.

Each record retains its product sourceURL and retrieval date. Source queries used the Polish-market filter and searches for twaróg and pierogi through https://pl.openfoodfacts.org/cgi/search.pl and https://world.openfoodfacts.org/cgi/search.pl. The snapshot is bundled separately and remains searchable offline; matching live product results take precedence when available.

Attribution: Open Food Facts contributors, https://world.openfoodfacts.org/. The database is available under the Open Database License (ODbL): https://opendatacommons.org/licenses/odbl/1-0/. Open Food Facts licensing guidance: https://github.com/openfoodfacts/openfoodfacts-server/blob/main/docs/api/tutorials/license-be-on-the-legal-side.md. No product images are included in this snapshot. Retain source attribution and applicable ODbL obligations when redistributing it.

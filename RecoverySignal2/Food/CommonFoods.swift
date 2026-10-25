//
//  CommonFoods.swift
//  RecoverySignal2
//
//  Everyday foods the Swiss database doesn't list — cooked chicken breast,
//  protein powder, Greek yogurt, noodles, wraps, popular snacks, cereals and
//  fast food. Values per 100 g are
//  typical figures: USDA FoodData Central where there's a generic entry, and
//  common supermarket labels for branded-style products (protein powder, bars,
//  skyr). Portions give a small, medium and large "one of it".
//

import Foundation

enum CommonFoods {
    struct Entry {
        let id: String
        let name: String
        /// Other words it should be found by (e.g. German names).
        let aliases: String
        let kcal: Double, protein: Double, carbs: Double, fat: Double
        var polishName: String? = nil
        var referenceFDCID: Int? = nil
        var portion: (unit: String, small: Double, medium: Double, large: Double)? = nil
        /// Grams per ml, for drinks.
        var density: Double? = nil
        /// Drink sizes in ml, when they differ in kind (glass, can, bottle).
        var servings: [(unit: String, ml: Double)]? = nil
    }

    static let entries: [Entry] = [
        // Everyday shortcuts: exact SR Legacy macros; app-defined typical edible servings.
        Entry(id: "everyday-172421", name: "Lentils, boiled", aliases: "linsen lentil Soczewica gotowana", kcal: 116.0, protein: 9.02, carbs: 20.13, fat: 0.38,
              polishName: "Soczewica gotowana", referenceFDCID: 172421, portion: (String(localized: "serving"), 75, 150, 225)),
        Entry(id: "everyday-173757", name: "Chickpeas, boiled", aliases: "kichererbsen garbanzo Ciecierzyca gotowana", kcal: 164.0, protein: 8.86, carbs: 27.42, fat: 2.59,
              polishName: "Ciecierzyca gotowana", referenceFDCID: 173757, portion: (String(localized: "serving"), 80, 160, 240)),
        Entry(id: "everyday-169967", name: "Broccoli, boiled", aliases: "brokkoli Brokuły gotowane", kcal: 35.0, protein: 2.38, carbs: 7.18, fat: 0.41,
              polishName: "Brokuły gotowane", referenceFDCID: 169967, portion: (String(localized: "serving"), 80, 150, 220)),
        Entry(id: "everyday-170397", name: "Cauliflower, boiled", aliases: "blumenkohl Kalafior gotowany", kcal: 23.0, protein: 1.84, carbs: 4.11, fat: 0.45,
              polishName: "Kalafior gotowany", referenceFDCID: 170397, portion: (String(localized: "serving"), 80, 150, 220)),
        Entry(id: "everyday-168463", name: "Spinach, boiled", aliases: "spinat Szpinak gotowany", kcal: 23.0, protein: 2.97, carbs: 3.75, fat: 0.26,
              polishName: "Szpinak gotowany", referenceFDCID: 168463, portion: (String(localized: "serving"), 60, 120, 180)),
        Entry(id: "everyday-168483", name: "Sweet potato, baked flesh", aliases: "süsskartoffel Batat pieczony, miąższ", kcal: 90.0, protein: 2.01, carbs: 20.71, fat: 0.15,
              polishName: "Batat pieczony, miąższ", referenceFDCID: 168483, portion: (String(localized: "serving"), 100, 150, 250)),
        Entry(id: "everyday-169700", name: "Couscous, cooked", aliases: "couscous kasza Kuskus gotowany", kcal: 112.0, protein: 3.79, carbs: 23.22, fat: 0.16,
              polishName: "Kuskus gotowany", referenceFDCID: 169700, portion: (String(localized: "serving"), 100, 150, 200)),
        Entry(id: "everyday-170287", name: "Bulgur, cooked", aliases: "bulgur kasza Kasza bulgur gotowana", kcal: 83.0, protein: 3.08, carbs: 18.58, fat: 0.24,
              polishName: "Kasza bulgur gotowana", referenceFDCID: 170287, portion: (String(localized: "serving"), 100, 150, 200)),
        Entry(id: "everyday-170285", name: "Pearl barley, cooked", aliases: "gerste kasza Kasza jęczmienna perłowa gotowana", kcal: 123.0, protein: 2.26, carbs: 28.22, fat: 0.44,
              polishName: "Kasza jęczmienna perłowa gotowana", referenceFDCID: 170285, portion: (String(localized: "serving"), 100, 150, 200)),
        Entry(id: "everyday-168917", name: "Quinoa, cooked", aliases: "quinoa komosa Komosa ryżowa gotowana", kcal: 120.0, protein: 4.4, carbs: 21.3, fat: 1.92,
              polishName: "Komosa ryżowa gotowana", referenceFDCID: 168917, portion: (String(localized: "serving"), 100, 150, 200)),
        Entry(id: "everyday-171662", name: "Instant porridge, plain, made with water", aliases: "oatmeal haferbrei owsianka Owsianka błyskawiczna na wodzie", kcal: 68.0, protein: 2.37, carbs: 11.67, fat: 1.36,
              polishName: "Owsianka błyskawiczna na wodzie", referenceFDCID: 171662, portion: (String(localized: "bowl"), 150, 250, 350)),
        Entry(id: "everyday-172454", name: "Hummus, homemade", aliases: "hummus pasta ciecierzyca Hummus domowy", kcal: 177.0, protein: 4.86, carbs: 20.12, fat: 8.59,
              polishName: "Hummus domowy", referenceFDCID: 172454, portion: (String(localized: "serving"), 30, 50, 80)),
        Entry(id: "everyday-170554", name: "Chia seeds, dry", aliases: "chia nasiona Nasiona chia suche", kcal: 486.0, protein: 16.54, carbs: 42.12, fat: 30.74,
              polishName: "Nasiona chia suche", referenceFDCID: 170554, portion: (String(localized: "serving"), 10, 20, 30)),
        Entry(id: "everyday-169414", name: "Flaxseed", aliases: "leinsamen flax len Siemię lniane", kcal: 534.0, protein: 18.29, carbs: 28.88, fat: 42.16,
              polishName: "Siemię lniane", referenceFDCID: 169414, portion: (String(localized: "serving"), 10, 20, 30)),
        Entry(id: "everyday-170187", name: "Walnuts, shelled", aliases: "walnuss walnuts Orzechy włoskie łuskane", kcal: 654.0, protein: 15.23, carbs: 13.71, fat: 65.21,
              polishName: "Orzechy włoskie łuskane", referenceFDCID: 170187, portion: (String(localized: "handful"), 15, 30, 45)),
        Entry(id: "everyday-170162", name: "Cashews, raw", aliases: "cashew nerkowce Orzechy nerkowca surowe", kcal: 553.0, protein: 18.22, carbs: 30.19, fat: 43.85,
              polishName: "Orzechy nerkowca surowe", referenceFDCID: 170162, portion: (String(localized: "handful"), 15, 30, 45)),
        Entry(id: "everyday-172470", name: "Peanut butter, smooth, unsalted", aliases: "erdnussbutter peanut Masło orzechowe gładkie bez soli", kcal: 598.0, protein: 22.21, carbs: 22.31, fat: 51.36,
              polishName: "Masło orzechowe gładkie bez soli", referenceFDCID: 172470, portion: (String(localized: "serving"), 10, 20, 30)),
        Entry(id: "everyday-171705", name: "Avocado, flesh", aliases: "avocado awokado Awokado, miąższ", kcal: 160.0, protein: 2.0, carbs: 8.53, fat: 14.66,
              polishName: "Awokado, miąższ", referenceFDCID: 171705, portion: (String(localized: "serving"), 50, 100, 150)),
        Entry(id: "everyday-171711", name: "Blueberries, raw", aliases: "heidelbeeren blueberries Borówki surowe", kcal: 57.0, protein: 0.74, carbs: 14.49, fat: 0.33,
              polishName: "Borówki surowe", referenceFDCID: 171711, portion: (String(localized: "serving"), 75, 125, 200)),
        Entry(id: "everyday-167762", name: "Strawberries, raw", aliases: "erdbeeren strawberries Truskawki surowe", kcal: 32.0, protein: 0.67, carbs: 7.68, fat: 0.3,
              polishName: "Truskawki surowe", referenceFDCID: 167762, portion: (String(localized: "serving"), 100, 150, 250)),
        Entry(id: "everyday-174683", name: "Grapes, red or green", aliases: "trauben grapes Winogrona czerwone lub zielone", kcal: 69.0, protein: 0.72, carbs: 18.1, fat: 0.16,
              polishName: "Winogrona czerwone lub zielone", referenceFDCID: 174683, portion: (String(localized: "serving"), 80, 150, 200)),
        Entry(id: "everyday-167776", name: "Pear, Bartlett, raw", aliases: "birne pear gruszka Gruszka Williams surowa", kcal: 63.0, protein: 0.39, carbs: 15.01, fat: 0.16,
              polishName: "Gruszka Williams surowa", referenceFDCID: 167776, portion: (String(localized: "pear"), 150, 180, 230)),
        Entry(id: "everyday-167793", name: "Apple, Fuji, with skin", aliases: "apfel apple jablko Jabłko Fuji ze skórką", kcal: 63.0, protein: 0.2, carbs: 15.22, fat: 0.18,
              polishName: "Jabłko Fuji ze skórką", referenceFDCID: 167793, portion: (String(localized: "apple"), 150, 190, 240)),
        Entry(id: "everyday-173944", name: "Banana, peeled", aliases: "banane banana Banan obrany", kcal: 89.0, protein: 1.09, carbs: 22.84, fat: 0.33,
              polishName: "Banan obrany", referenceFDCID: 173944, portion: (String(localized: "banana"), 90, 120, 150)),
        Entry(id: "everyday-170845", name: "Mozzarella, whole milk", aliases: "mozzarella ser Mozzarella z pełnego mleka", kcal: 299.0, protein: 22.17, carbs: 2.4, fat: 22.14,
              polishName: "Mozzarella z pełnego mleka", referenceFDCID: 170845, portion: (String(localized: "serving"), 30, 60, 125)),
        Entry(id: "everyday-173420", name: "Feta cheese", aliases: "feta käse cheese Ser feta", kcal: 265.0, protein: 14.21, carbs: 3.88, fat: 21.49,
              polishName: "Ser feta", referenceFDCID: 173420, portion: (String(localized: "serving"), 30, 50, 75)),
        Entry(id: "everyday-172475", name: "Tofu, firm, calcium-set", aliases: "tofu fest Tofu twarde, koagulowane wapniem", kcal: 144.0, protein: 17.27, carbs: 2.78, fat: 8.72,
              polishName: "Tofu twarde, koagulowane wapniem", referenceFDCID: 172475, portion: (String(localized: "serving"), 80, 150, 200)),
        Entry(id: "everyday-172467", name: "Tempeh, cooked", aliases: "tempeh Tempeh gotowany", kcal: 195.0, protein: 19.91, carbs: 7.62, fat: 11.38,
              polishName: "Tempeh gotowany", referenceFDCID: 172467, portion: (String(localized: "serving"), 75, 125, 175)),
        Entry(id: "everyday-173424", name: "Egg, hard-boiled", aliases: "ei egg jajka jajko Jajko gotowane na twardo", kcal: 155.0, protein: 12.58, carbs: 1.12, fat: 10.61,
              polishName: "Jajko gotowane na twardo", referenceFDCID: 173424, portion: (String(localized: "egg"), 45, 50, 60)),
        Entry(id: "everyday-170093", name: "Potato, baked, with skin", aliases: "kartoffel potato ziemniaki Ziemniak pieczony ze skórką", kcal: 93.0, protein: 2.5, carbs: 21.15, fat: 0.13,
              polishName: "Ziemniak pieczony ze skórką", referenceFDCID: 170093, portion: (String(localized: "potato"), 100, 180, 280)),
        Entry(id: "everyday-170686", name: "Buckwheat groats, roasted, cooked", aliases: "buchweizen buckwheat kasza Kasza gryczana prażona gotowana", kcal: 92.0, protein: 3.38, carbs: 19.94, fat: 0.62,
              polishName: "Kasza gryczana prażona gotowana", referenceFDCID: 170686, portion: (String(localized: "serving"), 100, 150, 200)),
        Entry(id: "everyday-169279", name: "Sauerkraut, canned, with liquid", aliases: "sauerkraut kapusta Kapusta kiszona konserwowa z zalewą", kcal: 19.0, protein: 0.91, carbs: 4.28, fat: 0.14,
              polishName: "Kapusta kiszona konserwowa z zalewą", referenceFDCID: 169279, portion: (String(localized: "serving"), 50, 100, 150)),

        // Protein products
        Entry(id: "whey", name: "Whey protein powder", aliases: "protein shake pulver", kcal: 380, protein: 78, carbs: 8, fat: 5,
              portion: (String(localized: "scoop"), 20, 30, 40)),
        Entry(id: "casein", name: "Casein protein powder", aliases: "protein pulver", kcal: 360, protein: 80, carbs: 6, fat: 2,
              portion: (String(localized: "scoop"), 20, 30, 40)),
        Entry(id: "plantprotein", name: "Plant protein powder (pea/rice)", aliases: "vegan protein pulver", kcal: 385, protein: 76, carbs: 7, fat: 7,
              portion: (String(localized: "scoop"), 20, 30, 40)),
        Entry(id: "proteinbar", name: "Protein bar (typical)", aliases: "proteinriegel", kcal: 350, protein: 33, carbs: 33, fat: 12,
              portion: (String(localized: "bar"), 40, 55, 65)),
        Entry(id: "proteinpudding", name: "High-protein pudding", aliases: "protein pudding", kcal: 75, protein: 10, carbs: 6, fat: 1.5,
              portion: (String(localized: "pot"), 150, 180, 200)),
        Entry(id: "seitan", name: "Seitan, prepared", aliases: "wheat gluten", kcal: 140, protein: 25, carbs: 6, fat: 2),
        Entry(id: "jerky", name: "Beef jerky", aliases: "trockenfleisch", kcal: 410, protein: 33, carbs: 11, fat: 25.6),

        // Dairy
        Entry(id: "greek0", name: "Greek yogurt, plain, 0% fat", aliases: "griechischer joghurt yoghurt", kcal: 59, protein: 10.3, carbs: 3.6, fat: 0.4,
              portion: (String(localized: "pot"), 150, 170, 200)),
        Entry(id: "greek5", name: "Greek yogurt, plain, 5% fat", aliases: "griechischer joghurt yoghurt", kcal: 96, protein: 9, carbs: 3.9, fat: 5,
              portion: (String(localized: "pot"), 150, 170, 200)),
        Entry(id: "skyr", name: "Skyr, plain", aliases: "yogurt joghurt", kcal: 63, protein: 11, carbs: 4, fat: 0.2,
              portion: (String(localized: "pot"), 150, 170, 200)),
        Entry(id: "magerquark", name: "Quark, low fat", aliases: "magerquark curd", kcal: 67, protein: 12, carbs: 4, fat: 0.2),
        Entry(id: "kefir", name: "Kefir, plain (3.5% fat)", aliases: "", kcal: 62, protein: 3.3, carbs: 4.2, fat: 3.5, density: 1.03),
        Entry(id: "ricotta", name: "Ricotta, whole milk", aliases: "", kcal: 174, protein: 11.3, carbs: 3, fat: 13),
        Entry(id: "halloumi", name: "Halloumi", aliases: "grill cheese käse", kcal: 321, protein: 21, carbs: 2.2, fat: 25),
        Entry(id: "gouda", name: "Gouda", aliases: "käse cheese", kcal: 356, protein: 24.9, carbs: 2.2, fat: 27.4),
        Entry(id: "cheddar", name: "Cheddar", aliases: "käse cheese", kcal: 403, protein: 24.9, carbs: 1.3, fat: 33.1),
        Entry(id: "gruyere", name: "Gruyère", aliases: "greyerzer käse cheese", kcal: 413, protein: 29.8, carbs: 0.4, fat: 32.3),

        // Meat, fish, eggs (cooked)
        Entry(id: "chickenbreastcooked", name: "Chicken breast, skinless, cooked", aliases: "pouletbrust grilled", kcal: 165, protein: 31, carbs: 0, fat: 3.6,
              portion: (String(localized: "breast"), 120, 170, 220)),
        Entry(id: "chickenthighcooked", name: "Chicken thigh, skinless, cooked", aliases: "pouletschenkel", kcal: 179, protein: 24.8, carbs: 0, fat: 8.2),
        Entry(id: "groundbeef5", name: "Ground beef, 5% fat, cooked", aliases: "minced hackfleisch rind", kcal: 170, protein: 26, carbs: 0, fat: 7),
        Entry(id: "porkchop", name: "Pork loin chop, lean, cooked", aliases: "schweinskotelett", kcal: 196, protein: 29, carbs: 0, fat: 8,
              portion: (String(localized: "chop"), 100, 140, 180)),
        Entry(id: "cookedham", name: "Cooked ham, lean", aliases: "hinterschinken schinken", kcal: 110, protein: 20, carbs: 1, fat: 3,
              portion: (String(localized: "slice"), 15, 25, 35)),
        Entry(id: "leberkaese", name: "Leberkäse (Fleischkäse)", aliases: "fleischkaese", kcal: 300, protein: 12, carbs: 1, fat: 28,
              portion: (String(localized: "slice"), 80, 120, 160)),
        Entry(id: "salmoncooked", name: "Salmon, farmed, cooked", aliases: "lachs", kcal: 206, protein: 22.1, carbs: 0, fat: 12.4,
              portion: (String(localized: "fillet"), 100, 125, 150)),
        Entry(id: "tunawater", name: "Tuna, canned in water, drained", aliases: "thunfisch", kcal: 116, protein: 25.5, carbs: 0, fat: 0.8,
              portion: (String(localized: "can"), 100, 130, 150)),
        Entry(id: "eggfried", name: "Egg, fried", aliases: "spiegelei", kcal: 196, protein: 13.6, carbs: 0.8, fat: 14.8,
              portion: (String(localized: "egg"), 40, 46, 54)),
        Entry(id: "eggscrambled", name: "Scrambled eggs", aliases: "rührei", kcal: 149, protein: 10, carbs: 1.6, fat: 11),
        Entry(id: "omelette", name: "Omelette, plain", aliases: "omelett", kcal: 154, protein: 10.6, carbs: 0.6, fat: 11.7),

        // Carbs (cooked) and bakery
        Entry(id: "ricewhitecooked", name: "Rice, white, cooked", aliases: "reis gekocht basmati jasmine", kcal: 130, protein: 2.7, carbs: 28.2, fat: 0.3),
        Entry(id: "ricebrowncooked", name: "Rice, brown, cooked", aliases: "vollkornreis reis gekocht", kcal: 123, protein: 2.7, carbs: 25.6, fat: 1),
        Entry(id: "eggnoodles", name: "Egg noodles, cooked", aliases: "nudeln", kcal: 138, protein: 4.5, carbs: 25.2, fat: 2.1),
        Entry(id: "ricenoodles", name: "Rice noodles, cooked", aliases: "reisnudeln", kcal: 108, protein: 1.8, carbs: 24, fat: 0.2),
        Entry(id: "udon", name: "Udon noodles, cooked", aliases: "nudeln", kcal: 105, protein: 2.6, carbs: 21.6, fat: 0.4),
        Entry(id: "wrap", name: "Tortilla wrap, wheat", aliases: "wrap weizen", kcal: 306, protein: 8.2, carbs: 50.8, fat: 7.6,
              portion: (String(localized: "wrap"), 40, 60, 75)),
        Entry(id: "corntortilla", name: "Tortilla, corn", aliases: "mais taco", kcal: 218, protein: 5.7, carbs: 44.6, fat: 2.9,
              portion: (String(localized: "tortilla"), 20, 26, 35)),
        Entry(id: "bagel", name: "Bagel, plain", aliases: "", kcal: 250, protein: 10.1, carbs: 48.9, fat: 1.5,
              portion: (String(localized: "bagel"), 70, 90, 110)),
        Entry(id: "burgerbun", name: "Burger bun", aliases: "brötchen hamburger bun", kcal: 279, protein: 9.5, carbs: 49.5, fat: 4.3,
              portion: (String(localized: "bun"), 50, 60, 80)),
        Entry(id: "englishmuffin", name: "English muffin", aliases: "toastie", kcal: 227, protein: 8.9, carbs: 44, fat: 1.7,
              portion: (String(localized: "muffin"), 55, 60, 70)),
        Entry(id: "blueberrymuffin", name: "Blueberry muffin", aliases: "muffin", kcal: 377, protein: 4.4, carbs: 53, fat: 16,
              portion: (String(localized: "muffin"), 60, 90, 120)),
        Entry(id: "brownie", name: "Brownie", aliases: "", kcal: 405, protein: 4.8, carbs: 63.9, fat: 16.3,
              portion: (String(localized: "piece"), 35, 55, 75)),
        Entry(id: "pancake", name: "Pancakes, plain", aliases: "pfannkuchen", kcal: 227, protein: 6.4, carbs: 28.3, fat: 9.7,
              portion: (String(localized: "pancake"), 40, 60, 80)),
        Entry(id: "ricecake", name: "Rice cakes", aliases: "reiswaffel puffed", kcal: 387, protein: 8.2, carbs: 81.5, fat: 2.8,
              portion: (String(localized: "cake"), 7, 9, 12)),
        Entry(id: "granola", name: "Granola", aliases: "knuspermüesli crunchy muesli", kcal: 450, protein: 9, carbs: 64, fat: 17),

        // Legumes and vegetables
        Entry(id: "blackbeans", name: "Black beans, cooked", aliases: "schwarze bohnen", kcal: 132, protein: 8.9, carbs: 23.7, fat: 0.5),
        Entry(id: "kidneybeans", name: "Kidney beans, cooked", aliases: "kidneybohnen", kcal: 127, protein: 8.7, carbs: 22.8, fat: 0.5),
        Entry(id: "bakedbeans", name: "Baked beans in tomato sauce", aliases: "bohnen", kcal: 78, protein: 4.7, carbs: 12.9, fat: 0.2),
        Entry(id: "peascooked", name: "Green peas, cooked", aliases: "erbsen", kcal: 78, protein: 5.2, carbs: 14.3, fat: 0.3),
        Entry(id: "corncooked", name: "Sweet corn, cooked", aliases: "mais", kcal: 96, protein: 3.4, carbs: 21, fat: 1.5),
        Entry(id: "guacamole", name: "Guacamole", aliases: "avocado dip", kcal: 150, protein: 2, carbs: 8.5, fat: 13),

        // Spreads, snacks, sweets
        Entry(id: "almondbutter", name: "Almond butter", aliases: "mandelmus", kcal: 614, protein: 21, carbs: 18.8, fat: 55.5),
        Entry(id: "dark85", name: "Dark chocolate, 85% cocoa", aliases: "schokolade", kcal: 584, protein: 12.5, carbs: 19, fat: 46,
              portion: (String(localized: "square"), 5, 10, 20)),
        Entry(id: "medjool", name: "Medjool dates", aliases: "datteln", kcal: 277, protein: 1.8, carbs: 75, fat: 0.2,
              portion: (String(localized: "date"), 18, 24, 30)),

        // Drinks
        Entry(id: "oatdrink", name: "Oat drink, plain", aliases: "hafermilch oat milk", kcal: 45, protein: 1, carbs: 6.5, fat: 1.5, density: 1.02),
        Entry(id: "cola", name: "Cola", aliases: "coca-cola coke", kcal: 42, protein: 0, carbs: 10.6, fat: 0,
              density: 1.04, servings: [(String(localized: "glass"), 250), (String(localized: "can"), 330), (String(localized: "bottle"), 500)]),
        Entry(id: "colazero", name: "Cola, zero sugar", aliases: "coke zero light", kcal: 0.3, protein: 0, carbs: 0, fat: 0,
              density: 1.0, servings: [(String(localized: "glass"), 250), (String(localized: "can"), 330), (String(localized: "bottle"), 500)]),

        // Breakfast and cereal
        Entry(id: "poptartstrawberry", name: "Pop-Tarts, frosted strawberry", aliases: "poptarts pop tarts toaster pastry kellogg", kcal: 385, protein: 4, carbs: 69, fat: 10,
              portion: (String(localized: "pastry"), 48, 50, 52)),
        Entry(id: "poptartchoc", name: "Pop-Tarts, chocolate", aliases: "poptarts pop tarts toaster pastry kellogg", kcal: 390, protein: 4.5, carbs: 68, fat: 11,
              portion: (String(localized: "pastry"), 48, 50, 52)),
        Entry(id: "frosties", name: "Frosted flakes (Frosties)", aliases: "kellogg cereal zucker flakes", kcal: 375, protein: 4.5, carbs: 84, fat: 0.6,
              portion: (String(localized: "bowl"), 30, 40, 60)),
        Entry(id: "cheerios", name: "Cheerios", aliases: "cereal", kcal: 357, protein: 12.9, carbs: 71, fat: 7,
              portion: (String(localized: "bowl"), 30, 40, 60)),
        Entry(id: "ricekrispies", name: "Rice Krispies", aliases: "kellogg cereal", kcal: 382, protein: 6, carbs: 87, fat: 1,
              portion: (String(localized: "bowl"), 30, 40, 60)),
        Entry(id: "hazelnutspread", name: "Hazelnut cocoa spread (Nutella)", aliases: "nutella nusscreme", kcal: 539, protein: 6.3, carbs: 57.5, fat: 30.9,
              portion: (String(localized: "spoon"), 10, 15, 20)),
        Entry(id: "granolabar", name: "Granola bar, oats & honey", aliases: "nature valley müesliriegel", kcal: 471, protein: 8, carbs: 64, fat: 19,
              portion: (String(localized: "bar"), 21, 42, 50)),

        // Sweets and snacks
        Entry(id: "oreo", name: "Oreo cookies", aliases: "biscuit keks", kcal: 471, protein: 5, carbs: 68, fat: 20,
              portion: (String(localized: "cookie"), 10, 11, 12)),
        Entry(id: "kitkat", name: "KitKat", aliases: "chocolate schokolade", kcal: 518, protein: 6.5, carbs: 60, fat: 27,
              portion: (String(localized: "bar"), 21, 42, 45)),
        Entry(id: "snickers", name: "Snickers", aliases: "chocolate bar schokoriegel", kcal: 481, protein: 8.6, carbs: 59, fat: 23,
              portion: (String(localized: "bar"), 25, 50, 75)),
        Entry(id: "mars", name: "Mars bar", aliases: "chocolate schokoriegel", kcal: 449, protein: 4, carbs: 70, fat: 17,
              portion: (String(localized: "bar"), 33, 51, 70)),
        Entry(id: "twix", name: "Twix", aliases: "chocolate schokoriegel", kcal: 495, protein: 4.5, carbs: 64, fat: 24,
              portion: (String(localized: "finger"), 25, 50, 75)),
        Entry(id: "toblerone", name: "Toblerone, milk", aliases: "chocolate schokolade", kcal: 525, protein: 5.4, carbs: 60.5, fat: 29,
              portion: (String(localized: "piece"), 8, 12, 35)),
        Entry(id: "mmpeanut", name: "M&M's, peanut", aliases: "mms chocolate", kcal: 516, protein: 9.6, carbs: 57, fat: 26,
              portion: (String(localized: "pack"), 45, 90, 250)),
        Entry(id: "goldbears", name: "Gummy bears (Haribo)", aliases: "haribo goldbären gummibärchen", kcal: 343, protein: 6.9, carbs: 77, fat: 0.5,
              portion: (String(localized: "handful"), 15, 30, 100)),
        Entry(id: "pringles", name: "Pringles, original", aliases: "chips crisps", kcal: 536, protein: 4.3, carbs: 51, fat: 35,
              portion: (String(localized: "handful"), 15, 30, 40)),
        Entry(id: "doritos", name: "Doritos, nacho cheese", aliases: "tortilla chips", kcal: 498, protein: 7, carbs: 58, fat: 26,
              portion: (String(localized: "handful"), 15, 30, 40)),
        Entry(id: "salsa", name: "Salsa dip", aliases: "tomato dip", kcal: 36, protein: 1.5, carbs: 6.5, fat: 0.2),
        Entry(id: "glazeddonut", name: "Glazed donut", aliases: "doughnut krapfen", kcal: 388, protein: 4.1, carbs: 45, fat: 22,
              portion: (String(localized: "donut"), 45, 50, 60)),
        Entry(id: "magnum", name: "Magnum ice cream, classic", aliases: "glace eis ice cream bar", kcal: 302, protein: 3.8, carbs: 27, fat: 20,
              portion: (String(localized: "bar"), 70, 79, 90)),
        Entry(id: "cookiedoughicecream", name: "Ice cream, cookie dough (Ben & Jerry's)", aliases: "glace eis", kcal: 270, protein: 4, carbs: 31, fat: 14,
              portion: (String(localized: "scoop"), 50, 70, 100)),

        // Fast food and ready meals
        Entry(id: "bigmac", name: "Big Mac (McDonald's)", aliases: "burger mcdonalds", kcal: 240, protein: 12, carbs: 20, fat: 12,
              portion: (String(localized: "burger"), 200, 215, 230)),
        Entry(id: "fastfoodfries", name: "Fries, fast food (McDonald's)", aliases: "pommes frites mcdonalds", kcal: 312, protein: 3.4, carbs: 41, fat: 15,
              portion: (String(localized: "portion"), 80, 114, 150)),
        Entry(id: "nuggets", name: "Chicken nuggets, fast food", aliases: "mcnuggets mcdonalds", kcal: 245, protein: 14, carbs: 17, fat: 13,
              portion: (String(localized: "nugget"), 15, 17, 20)),
        Entry(id: "frozenpizza", name: "Frozen pizza, mozzarella (Ristorante)", aliases: "tiefkühlpizza dr oetker", kcal: 262, protein: 10, carbs: 25, fat: 13,
              portion: (String(localized: "pizza"), 170, 335, 355)),

        // Drinks
        Entry(id: "rivella", name: "Rivella, red", aliases: "rivella rot", kcal: 31, protein: 0, carbs: 7.4, fat: 0,
              density: 1.03, servings: [(String(localized: "glass"), 250), (String(localized: "can"), 330), (String(localized: "bottle"), 500)]),
        Entry(id: "smoothie", name: "Fruit smoothie, strawberry & banana", aliases: "innocent", kcal: 55, protein: 0.6, carbs: 12, fat: 0.1,
              density: 1.05, servings: [(String(localized: "glass"), 200), (String(localized: "bottle"), 250), (String(localized: "bottle"), 750)]),
        Entry(id: "icedlatte", name: "Iced coffee latte, ready to drink", aliases: "emmi caffè latte eiskaffee", kcal: 69, protein: 3, carbs: 10, fat: 1.9,
              density: 1.03, servings: [(String(localized: "cup"), 230), (String(localized: "cup"), 370), (String(localized: "bottle"), 500)]),

        // Dishes
        Entry(id: "sushinigiri", name: "Sushi, salmon nigiri", aliases: "sushi", kcal: 150, protein: 6.5, carbs: 22, fat: 3.5,
              portion: (String(localized: "piece"), 30, 40, 50)),
        Entry(id: "sushimaki", name: "Sushi, maki roll (fish)", aliases: "sushi california roll", kcal: 145, protein: 5.5, carbs: 25, fat: 2.5,
              portion: (String(localized: "piece"), 20, 28, 35)),
        Entry(id: "pokebowl", name: "Poke bowl, salmon", aliases: "bowl", kcal: 140, protein: 8, carbs: 15, fat: 5,
              portion: (String(localized: "bowl"), 350, 450, 550)),
    ]

    static var items: [FoodItem] {
        entries.map { e in
            FoodItem(id: "common-\(e.id)", name: AppLanguage.current == .polish ? (e.polishName ?? e.name) : e.name, brand: nil, kcal: e.kcal, protein: e.protein, carbs: e.carbs, fat: e.fat,
                     source: .common, barcode: nil, servingGrams: nil, density: e.density)
        }
    }

    static func portions(for item: FoodItem) -> [FoodPortion] {
        guard item.source == .common,
              let entry = entries.first(where: { "common-\($0.id)" == item.id }) else { return [] }
        if let servings = entry.servings, servings.count == 3 {
            let density = entry.density ?? 1
            return zip(FoodPortion.Size.allCases, servings).map { size, s in
                FoodPortion(size: size, unit: s.unit, grams: s.ml * density, ml: s.ml)
            }
        }
        guard let p = entry.portion else { return FoodPortions.drinkPortions(for: item) }
        return [FoodPortion(size: .small, unit: p.unit, grams: p.small),
                FoodPortion(size: .medium, unit: p.unit, grams: p.medium),
                FoodPortion(size: .large, unit: p.unit, grams: p.large)]
    }
}

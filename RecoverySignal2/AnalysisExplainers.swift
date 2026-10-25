//
//  AnalysisExplainers.swift
//  RecoverySignal2
//
//  Plain-English explanations for every metric, trend and analysis card: what
//  the number means, why it matters, how it's worked out step by step, how to
//  read yours, and where it falls short. They open from the ⓘ on each card.
//  The steps here must stay in step with the models they describe.
//

import SwiftUI

struct Explainer {
    let title: String
    /// What this measures, for someone who has never heard of it.
    let what: String
    /// Why it's worth looking at.
    let why: String
    /// How the number is worked out, one plain sentence per step.
    let steps: [String]
    /// A worked example with real-looking numbers.
    let example: String?
    /// How to interpret your own number.
    let reading: String
    /// Where it can mislead you.
    let limits: String
}

// MARK: - Recovery, strain and sleep

extension Explainer {

    static let recovery = Explainer(
        title: "Recovery score",
        what: "A percentage that says how ready your body is to take on hard training today. It isn't a measurement of anything on its own. It compares how your body behaved overnight with how it normally behaves for you.",
        why: "Your heart and nervous system react to stress, hard training, poor sleep, alcohol and illness before you feel anything. Recovery turns those hidden signals into one number so you can decide whether today is a day to push or to ease off.",
        steps: [
            "The app looks at your last 30 days (it needs at least 7) to learn what is normal for you: your usual overnight HRV, resting heart rate and breathing rate, and how much they vary from day to day.",
            "This morning's HRV is compared with that normal. Higher than usual counts in your favour, lower counts against you. The further from normal, the bigger the effect.",
            "Resting heart rate is compared the same way, except lower than usual is the good direction.",
            "Breathing rate is scored on steadiness. A calm, ordinary reading scores well, and a big jump in either direction scores poorly.",
            "Sleep is scored as the hours you slept divided by the hours you needed, capped at 100%.",
            "The four are blended: HRV counts for half, resting heart rate and sleep for a fifth each, and breathing for a tenth."
        ],
        example: "Your HRV is a little above your normal, resting heart rate is exactly normal, breathing is steady and you got 90% of the sleep you needed. That blends to roughly 70%, a yellow-to-green day.",
        reading: "67–100% (green): primed for hard training. 34–66% (yellow): train normally, don't chase records. 0–33% (red): prioritise rest. An entirely average day lands around 60–70%. Reaching 100% needs every signal to be clearly better than your normal at once, so it's rare.",
        limits: "The weightings are a sensible design choice, not a clinically validated score. Apple Watch measures HRV in a way (SDNN) that differs from the research standard, and alcohol, illness, stress or a late meal can move the same signals as training fatigue, so a low score tells you something is off but not what."
    )

    static let strain = Explainer(
        title: "Day strain",
        what: "How much cardiovascular work your body has done today, on a 0–21 scale. It counts your whole day, not only workouts, because walking uphill or carrying shopping raises your heart rate too.",
        why: "Recovery tells you how ready you are. Strain tells you what you've spent. Together they show whether you are matching effort to capacity.",
        steps: [
            "Your heart rate is read throughout the day and expressed as a share of your working range, from resting heart rate up to your maximum.",
            "Each minute is given a weight by how hard your heart was working: 0 for easy, then 1, 2, 3, 4 and up to 5 for near-maximal effort.",
            "The weighted minutes are added up into one load figure for the day.",
            "That load is converted to the 0–21 scale with a curve that flattens out, so each extra point is harder to earn than the last."
        ],
        example: "A day of ordinary movement plus a 45-minute run at a steady effort might add up to a strain of about 12: solid but not draining.",
        reading: "0–9 light, 10–13 moderate, 14–17 high, 18–21 all out. Because the scale gets harder as it climbs, going from 5 to 6 takes far less effort than going from 18 to 19.",
        limits: "It relies on the Watch sampling your heart rate often, and it samples much more densely during a recorded workout, so a hard effort you didn't record can read low. Heart rate also doesn't capture the muscular load of heavy lifting well."
    )

    static let sleepNeed = Explainer(
        title: "Sleep need",
        what: "How much sleep your body is asking for tonight. It isn't a fixed 8 hours. It starts from your personal baseline and moves up or down with what you did and how you've been sleeping.",
        why: "The same 7 hours can be plenty after an easy day and not enough after a hard one. Knowing tonight's real need lets you plan bedtime instead of guessing.",
        steps: [
            "Baseline: the app finds nights that were followed by good recovery (higher HRV, lower resting heart rate, a healthy share of deep and REM sleep) and takes the typical length of those. Until it has learned you, it blends toward 7.6 hours.",
            "Strain: a hard day adds extra time. The addition grows quickly for very hard days and is capped at about an hour and a quarter.",
            "Sleep debt: recent shortfall is added in full, and older unpaid debt counts at half, up to 2 hours. Sleeping extra pays it down.",
            "Naps: any daytime sleep between 11:00 and 19:00 is subtracted.",
            "Sleep performance is the hours you actually slept divided by this need, capped at 100%."
        ],
        example: "Baseline 7h 40m, plus 30 minutes for a hard day, plus 20 minutes of debt, minus a 20-minute nap gives a need of 8h 10m tonight.",
        reading: "85% performance or better is a solid night. Below 70% is a short night that will probably weigh on tomorrow's recovery. Note the same 7 hours can be 96% one night and 78% another because the need moves.",
        limits: "Your baseline needs a few weeks of Watch-tracked sleep with HRV before it becomes truly personal. Naps only count if something records them in Apple Health."
    )

    static let sleepPlanner = Explainer(
        title: "Tonight's bedtime",
        what: "The time to be in bed so that you reach tonight's sleep need before your alarm, allowing for the time it takes you to fall asleep and the time you're usually awake during the night.",
        why: "Most people know when they wake up but not when they should go to bed. Working backwards from the wake time removes the guesswork, including any sleep debt you are carrying.",
        steps: [
            "Wake time comes from your usual wake time over the last four weeks, a fixed time you set, or a one-off for tomorrow.",
            "The sleep target is tonight's sleep need scaled by the goal you choose (minimum, balanced or full).",
            "Time awake during the night is added, based on your own typical share, up to 15%.",
            "Time to fall asleep is added, using the median of your recent nights (15 minutes until it has learned you).",
            "Counting back from your wake time gives the moment to be in bed, shown as a 30-minute window around it.",
            "If that is more than an hour earlier than your usual bedtime, the plan also offers a gentler first step: 45 minutes earlier than usual."
        ],
        example: "Wake at 06:30, need 8h 00m, 30 minutes awake in the night and 15 minutes to fall asleep means being in bed by about 21:45.",
        reading: "Be in bed with the lights out at the start of the window. Keeping bedtimes within about 30 minutes of each other matters as much for sleep quality as total hours.",
        limits: "Time to fall asleep is measured from when your Watch starts tracking or Health records you in bed, so reading or scrolling first makes it look longer. Nights without a start marker aren't counted."
    )
}

// MARK: - Training and fatigue

extension Explainer {

    static let acwr = Explainer(
        title: "Training load ratio",
        what: "Compares how hard you trained this past week with what your body has been used to over the past month. It tells you whether you are building up sensibly or ramping up too fast.",
        why: "Injuries and burnout are rarely caused by hard training alone. They tend to follow a sudden jump. This ratio spots the jump early.",
        steps: [
            "Every session is scored by how hard it was for your heart: minutes trained, weighted heavily towards time spent near your maximum.",
            "The scores of the last 7 days are averaged, with recent days counting a little more. This is your 'acute' load.",
            "The scores of the last 28 days are averaged the same way. This is your 'chronic' load, what you're used to.",
            "Acute divided by chronic is the ratio."
        ],
        example: "If you usually do the equivalent of 300 load points a week and this week you did 420, the ratio is 1.4: quite a jump.",
        reading: "Below 0.8: training less than usual, fine as a deload. 0.8–1.3: the sweet spot. 1.3–1.5: ramping up fast, hold steady. Above 1.5: a spike, the zone linked to higher injury risk.",
        limits: "It comes from team-sport research that scientists still debate. Women use slightly different constants. Lifting sessions logged without heart rate use an estimated intensity. Treat it as a gauge of how fast you are ramping up, not a prediction of injury."
    )

    static let fatigue = Explainer(
        title: "Fatigue index",
        what: "Combines four signals (HRV, resting heart rate, sleep and training load) into one number that shows how today compares with your own normal, not anyone else's.",
        why: "Any single signal can be noisy. When several move in the same direction, it is much more likely to be real fatigue than a blip.",
        steps: [
            "For each signal, the app measures how far today is from your 6-week average, in units of how much that signal usually varies.",
            "HRV and sleep count in your favour when they are higher. Resting heart rate and training load count against you when they are higher.",
            "The four adjusted values are added together and scaled, so the result doesn't depend on how many signals were available."
        ],
        example: "HRV a bit low, resting heart rate a bit high, sleep short and training load high all point the same way, giving a clearly negative number.",
        reading: "0 is a normal day for you. Negative means more worn down than usual, positive means fresher. Below −1.5 for two or more days in a row means fatigue is building, not just one rough night.",
        limits: "It needs about two weeks of history. Illness, alcohol, stress and travel move the same signals, so it says something is off, not why."
    )

    static let hrvStability = Explainer(
        title: "HRV stability",
        what: "Measures how much your HRV jumps around from day to day, rather than what its average is. HRV (heart rate variability) is the small variation in the time between heartbeats, a window into how your nervous system is coping.",
        why: "Growing swings can be an early warning of overreaching even while the average still looks fine. A settled system tends to give steady readings.",
        steps: [
            "The last 7 days of HRV are taken and converted with a logarithm, which keeps big and small values comparable.",
            "The spread of those seven values is measured relative to their average. This is the 'coefficient of variation'.",
            "It is compared with your typical spread over the past month."
        ],
        example: "If your usual week-to-week spread is 8% and this week it is 11%, your HRV has become about a third more erratic than normal.",
        reading: "Close to your own baseline means a stable nervous system. More than 25% above your baseline counts as destabilising. It's worth easing off if other signals agree.",
        limits: "Research uses a different HRV measure (rMSSD) from the one Apple Watch records (SDNN). The idea carries over but published cut-offs don't, so it is only ever compared with your own history."
    )

    static let sleepDebt = Explainer(
        title: "Sleep debt",
        what: "How far behind on sleep you've fallen over the last two weeks: the total hours you owe your body.",
        why: "Short nights add up. One 6-hour night is fine, but a fortnight of them quietly lowers HRV, raises resting heart rate and hurts training.",
        steps: [
            "For each of the last 14 nights, the app compares what you slept with an 8-hour target.",
            "Nights shorter than the target add to the debt.",
            "A long night pays back at most 1 hour, because you can't fully 'bank' sleep in one go.",
            "The debt is the running total, and it never goes below zero."
        ],
        example: "Sleeping 6.5 hours for five nights is 7.5 hours short. A 9-hour weekend night pays back 1 hour, leaving about 6.5 hours of debt.",
        reading: "Under about 3 hours is fine. 5 hours or more is noticeable and usually shows up in HRV and resting heart rate within a few days.",
        limits: "It uses a flat 8-hour target, but your real need may be higher or lower. Watches can mistake lying still while awake for sleep."
    )
}

// MARK: - Energy and body composition

extension Explainer {

    static let tdee = Explainer(
        title: "Energy burned per day",
        what: "How many calories you actually burn in a day, worked out from what you eat and what your body weight really does, rather than from a generic formula.",
        why: "Calorie targets are only as good as the burn figure behind them. Formulas can be off by hundreds of calories for an individual. Your own weight response is the truth.",
        steps: [
            "Your daily weigh-ins are smoothed with a 7-day weighted average to remove day-to-day water changes.",
            "The app measures how fast that smooth line rose or fell per day over the last 21 days.",
            "A kilogram of body weight is worth about 7,700 kilocalories, so the daily change is converted into calories stored or lost.",
            "Your average intake minus those stored calories is what you must have burned."
        ],
        example: "You ate 2,400 kcal a day and your trend weight fell 0.1 kg per week, which is about 110 kcal a day. So you burned roughly 2,510 kcal.",
        reading: "This is roughly what you could eat to stay the same weight. If it agrees with the maintenance estimate on Today, both are trustworthy.",
        limits: "Only as good as your food logging: forgotten snacks make it read low. Water and stored-carb swings add noise, which is what the ± range shows. It needs 14 or more days with both weight and food logged."
    )

    static let energyAvailability = Explainer(
        title: "Energy availability",
        what: "How much energy is left for your body's basic upkeep after exercise, per kilogram of lean mass. It is the standard screening tool for under-fuelling, known clinically as RED-S.",
        why: "Eating too little for how much you train can quietly lower hormones, weaken bones and stall recovery long before you feel unwell.",
        steps: [
            "Your average calories eaten over the last 7 days are taken.",
            "Calories burned during workouts are subtracted.",
            "The remainder is divided by your fat-free (lean) mass in kilograms, taken from a smart scale or worked out from your weight and body-fat percentage."
        ],
        example: "Eating 2,600 kcal, burning 500 in training, with 65 kg of lean mass gives (2,600 − 500) ÷ 65 = 32 kcal per kg.",
        reading: "45 or more: adequate. 30–45: reduced, acceptable for a short planned cut. Below 30: low, the level linked to hormone, bone and recovery problems.",
        limits: "Needs body-fat or lean-mass data from a smart scale, and home scales estimate body fat loosely. It is a screening signal, not a diagnosis."
    )

    static let pRatio = Explainer(
        title: "Lean share of weight change",
        what: "Of the weight you've gained or lost recently, how much was lean mass (muscle, water, organs) rather than fat. It's called the partitioning ratio, or P-ratio.",
        why: "Gaining 2 kg of muscle and gaining 2 kg of fat look identical on the scale. This is how you tell whether a bulk or a cut is doing what you want.",
        steps: [
            "Your lean mass and fat mass readings are each smoothed over up to 6 weeks.",
            "The change in lean mass is divided by the total change in weight.",
            "It only reports once the total change is at least half a kilogram, otherwise noise would dominate."
        ],
        example: "You gained 1.6 kg in six weeks and lean mass rose 0.9 kg. The lean share is 0.9 ÷ 1.6, about 56%.",
        reading: "When gaining, higher is better: over 50% means most of the gain was lean. When losing, lower is better: under 20% means mostly fat was lost and muscle was kept.",
        limits: "Smart-scale body fat is noisy from day to day, so this only means something over several weeks and with at least 0.5 kg of total change."
    )

    static let adaptiveMaintenance = Explainer(
        title: "Maintenance calories",
        what: "The number of calories that holds your weight steady, learned from you rather than guessed. It starts from what your Watch says you burn and adjusts each day you log food.",
        why: "Every calorie target, from cutting to building, is built on this number. A wrong maintenance means a wrong plan.",
        steps: [
            "Your weight is smoothed over about 10 days so that water and salt swings don't fool it.",
            "Each day, the app works out what you must have burned: calories eaten minus the calories stored or lost according to the smoothed weight change.",
            "That day's figure nudges the running estimate a little (about a tenth of the gap). One odd day can't move it far, and each day is capped at ±1,000 kcal from the current estimate.",
            "The estimate starts from your Watch's resting plus active energy, and takes over as the basis for targets once 10 or more days are logged in four weeks."
        ],
        example: "You eat 2,500 kcal a day and your smoothed weight stays flat, so the estimate settles near 2,500. If your weight starts to fall, the estimate rises: you were burning more than thought.",
        reading: "The line on the card shows every adjustment, and the dashed line is where it started. A steady line means it has found your level.",
        limits: "Only as good as your logging: untracked food makes maintenance read low. Water, salt and stored-carb swings can shift the scale for days, which is why weight is smoothed and each day moves the estimate only a little."
    )

    static let intakeBalance = Explainer(
        title: "Does your food log match your body?",
        what: "What you must actually have eaten, worked out backwards from what your body burned and what your weight did. Research teams use this 'intake-balance' method to check food diaries without watching people eat.",
        why: "Almost everyone under-logs a little. This shows how big the gap is, so you can trust or correct your numbers.",
        steps: [
            "Expenditure: your Watch's resting plus active energy, using only days it was worn all day.",
            "Stored per day: the slope of your weight over four weeks, turned into calories. A kilogram is worth 7,700 kcal by default, or a value refined by your body-fat data (fat and lean tissue store different amounts of energy).",
            "Implied intake is expenditure plus the calories stored per day.",
            "The logging ratio is what you logged divided by that implied intake."
        ],
        example: "You burned 2,700 kcal, gained a little weight (worth +150 kcal a day) so implied intake is 2,850. You logged 2,400, so your ratio is 84%: about 450 kcal a day is missing.",
        reading: "Near 100% means your food log matches what your body did. Much below 100% usually means untracked food such as oils, drinks and weekends. Above 100% often means the Watch under-reads your expenditure.",
        limits: "Watch energy estimates are typically off by 15–25% in absolute terms, so this is best for spotting drift over weeks, not exact calories. Water and stored-carb swings distort short windows, which is why it uses four weeks."
    )

    static let weightForecast = Explainer(
        title: "Weight forecast",
        what: "Where your weight is heading if you keep eating like the last two weeks. Unlike the '7,700 kcal = 1 kg forever' rule, it accounts for your body burning less as you lose weight and more as you gain, so change slows as you approach a plateau.",
        why: "The simple rule promises endless steady loss, which never happens. This shows the realistic curve, including when you'll level off.",
        steps: [
            "The calorie gap is your average intake over 14 days minus your burn (the learned maintenance).",
            "Your body responds to each kilogram gained or lost by shifting its burn by about 22 kcal a day. This comes from a well-known model of body weight (Hall et al., The Lancet, 2011).",
            "That feedback means weight approaches a plateau gradually. The plateau is your current weight plus the calorie gap divided by 22.",
            "The shaded band carries the uncertainty in your maintenance estimate through the same maths."
        ],
        example: "A daily gap of −440 kcal leads to a plateau about 20 kg lower in theory, but the first kilograms come off much faster than the last.",
        reading: "The solid line uses your current intake, and the dashed line uses your goal's calorie target. Half the distance to the plateau is covered in roughly the half-life shown.",
        limits: "A simplified version of the NIH body-weight planner, fitted to your own burn. It assumes intake and activity stay the same, which real life rarely does. Treat the band as the minimum uncertainty."
    )

    static let expenditure = Explainer(
        title: "Where your calories go",
        what: "A breakdown of your daily calorie burn into resting, exercise, everyday movement and digestion. The everyday movement part is called NEAT (non-exercise activity thermogenesis): pacing, fidgeting, chores and walking about.",
        why: "When people diet, NEAT is often what quietly drops, sometimes cancelling a large share of the calorie deficit without them noticing.",
        steps: [
            "Resting: the Watch's resting energy.",
            "Exercise: energy logged inside workouts.",
            "NEAT: total active energy minus exercise energy.",
            "Digestion: about 10% of the calories you log eating.",
            "NEAT change compares the last 14 days with the 6 weeks before."
        ],
        example: "If your non-workout movement burned 550 kcal a day and now burns 450, NEAT has fallen about 18%, a classic sign of your body conserving energy.",
        reading: "A NEAT drop of more than about 15% while cutting is a typical adaptive response. More steps and less sitting can win it back without extra training.",
        limits: "Apple Watch doesn't measure NEAT directly. This splits active energy using workout time, so an unrecorded walk counts as NEAT and an unrecorded session inflates it."
    )
}

// MARK: - Health markers

extension Explainer {

    static let heartRateRecovery = Explainer(
        title: "Heart rate recovery",
        what: "How many beats per minute your heart rate falls in the first minute after a workout ends. It reflects how quickly the calming part of your nervous system takes back control.",
        why: "It's a fitness marker, and in large studies a slow recovery predicted higher risk of early death. It tends to improve as you get fitter.",
        steps: [
            "Apple Watch records your heart rate at the end of a workout started in the Workout app.",
            "It records it again 60 seconds later.",
            "Heart rate recovery is the difference between the two.",
            "The card shows the average of the last 60 days, compared with typical bands."
        ],
        example: "If you finish a run at 165 bpm and are at 140 a minute later, your recovery is 25 bpm: a good result.",
        reading: "Under about 12 is low, 13–20 normal, 21–29 good and 30 or more excellent. A rising trend over months means your cardiovascular fitness is improving. A value of 12 or less was linked with higher risk in a well-known 1999 study.",
        limits: "It depends heavily on how you stop: a walking cool-down, standing still and sitting all give different numbers. Compare like with like."
    )

    static let vo2Max = Explainer(
        title: "VO₂ max",
        what: "The most oxygen your body can use, per kilogram of body weight, per minute. It's the best single measure of aerobic fitness.",
        why: "It is one of the strongest single predictors of lifespan. In a large 2018 study, low fitness carried more risk than smoking.",
        steps: [
            "Apple Watch estimates it during outdoor walks, runs and hikes, using your heart rate against your pace.",
            "The app compares your value with typical values for your age and sex, based on widely used fitness charts.",
            "Fitness age is the age at which your value would be average."
        ],
        example: "A 35-year-old whose VO₂ max is typical for a 27-year-old has a fitness age of 27.",
        reading: "Each category step up is a meaningful drop in long-term risk. VO₂ max naturally falls about 10% per decade, so holding steady as you age is itself a win.",
        limits: "Watch estimates are within about ±5 ml/kg/min of lab tests at the group level. Age and sex must be set in the Health app for the right comparison. Without them it assumes a 30-year-old man."
    )

    static let sleepCoupling = Explainer(
        title: "How sleep connects to your body",
        what: "Whether your own data shows links between sleep and everything else: does deep sleep lift your HRV the next morning, do short nights raise your heart rate or appetite, do hard days change your deep sleep.",
        why: "General advice about sleep is only half useful. This tells you which links are actually strong for you.",
        steps: [
            "The app pairs up matching nights and days from the last 120 days, for example deep sleep with the next morning's HRV.",
            "For each pair of measures it calculates the correlation: how consistently they rise and fall together, from −1 to +1.",
            "It also works out how likely that pattern is to be pure chance, and requires at least 14 pairs before reporting anything."
        ],
        example: "If more deep sleep goes with a higher HRV the next morning on most nights, the correlation might come out around +0.4: a moderate link.",
        reading: "Under 0.1 means no link, 0.1–0.3 weak, 0.3–0.5 moderate, above 0.5 strong. 'Significant' means it's unlikely to be chance alone (less than a 5% probability).",
        limits: "Correlation is not cause: a stressful week can shorten sleep and lower HRV at the same time. With many pairs tested, one 'significant' result can still be a fluke."
    )

    static let activitySpectrum = Explainer(
        title: "Activity intensity",
        what: "How your movement splits across gentle, moderate and vigorous intensity, compared with the World Health Organization's guideline of 150–300 moderate minutes a week.",
        why: "That guideline is the dose linked with the biggest fall in heart disease and early death. Intensity matters as much as time.",
        steps: [
            "Your heart rate is turned into a share of your working range (resting to maximum).",
            "30–40% counts as light, 40–60% as moderate and 60% or more as vigorous.",
            "Vigorous minutes count double: the weekly total is moderate minutes plus twice the vigorous minutes.",
            "Without heart-rate data, it falls back to Apple's exercise minutes."
        ],
        example: "100 moderate minutes plus 40 vigorous minutes counts as 100 + 80 = 180 minutes, comfortably past the 150-minute minimum.",
        reading: "Hitting 150 is the big win, and 300 adds more. For muscle gain, keep most of it moderate so it doesn't eat into recovery from lifting.",
        limits: "Heart rate also rises with heat, caffeine and stress, and the Watch samples less often outside workouts, so everyday minutes are under-counted."
    )

    static let mobility = Explainer(
        title: "Walking quality",
        what: "How you walk, measured by your iPhone in your pocket: speed, step length, how even your two sides are, and how steady you are. Gait speed is sometimes called the 'sixth vital sign'.",
        why: "In studies of older adults, walking speed predicted survival about as well as age and chronic disease combined. For younger people, changes flag injuries early.",
        steps: [
            "The iPhone records walking speed, step length, asymmetry, double-support time and steadiness during normal walking.",
            "The app compares the last 30 days with the 3 months before.",
            "Walking speed is banded: 1.3 m/s or more is brisk, 1.0–1.3 healthy, 0.8–1.0 slower, and under 0.8 is in the range linked to frailty."
        ],
        example: "A jump in asymmetry from 2% to 8% often shows up when something hurts, before you consciously start limping.",
        reading: "For someone young and training, these mostly confirm things are fine and flag injuries early.",
        limits: "Only measured when the phone is carried at hip height on flat ground. The frailty thresholds come from older populations."
    )

    static let allostaticLoad = Explainer(
        title: "Wear-and-tear score",
        what: "A score for whether several stress systems (heart, nervous system, sleep, activity, breathing) are running worse than your long-term normal at the same time. 'Allostatic load' is the medical name for cumulative wear from stress.",
        why: "One system drifting is common. Several drifting together is what predicts trouble, so this looks at the whole picture.",
        steps: [
            "Six weekly averages are tracked: resting heart rate, HRV, heart rate recovery, sleep, active minutes and breathing rate.",
            "Each is compared with your own long-term weekly average and scaled by how much it usually varies.",
            "They are signed so that a positive number always means more wear than normal.",
            "The index is the average of those numbers. It needs at least 8 weeks of data for each input.",
            "The high-risk count is the number of inputs currently in their worst quarter."
        ],
        example: "Resting heart rate up, HRV down and sleep short for three weeks running would push the index above 0.5.",
        reading: "Below 0.5 is typical for you. 0.5–1 means several systems are strained together, so back off before it compounds. Watch the long-term trend: lifestyle changes should pull it down over months.",
        limits: "Clinical versions use blood pressure, cholesterol, cortisol and blood sugar, which a Watch can't measure. This compares you with yourself, not with the population."
    )

    static let patterns = Explainer(
        title: "Patterns in your data",
        what: "A search through your own history for things you do on one day that line up with how your body responds one to three days later, such as protein intake against next-day HRV.",
        why: "It turns months of numbers into a short list of ideas worth testing on yourself.",
        steps: [
            "Every input on day d is paired with every outcome on days d+1, d+2 and d+3.",
            "For each pair, a rank correlation is calculated: how consistently the two rise and fall together, without assuming a straight line.",
            "The chance that the pattern is random is worked out.",
            "A finding is only kept if the link is at least moderate, there are at least 21 days of data, and it survives a strict correction for testing many pairs at once (so that a few flukes don't slip through)."
        ],
        example: "Higher carbs in the evening might go with better deep sleep the same night, in a consistent way across six weeks.",
        reading: "The number runs from −1 to +1. Positive means more of the input tends to come with more of the outcome. About ±0.3 is weak, ±0.35 moderate and ±0.5 or more strong.",
        limits: "Correlation, not cause: a hard training day changes food, sleep and HRV all at once. Treat findings as ideas to test on purpose, not rules."
    )
}

// MARK: - Trends: the basic measurements

extension Explainer {

    static let hrv = Explainer(
        title: "Heart rate variability (HRV)",
        what: "The tiny natural variation in the time between one heartbeat and the next, measured in milliseconds. A relaxed, recovered body has a more variable heartbeat, not a steadier one.",
        why: "HRV is one of the most sensitive early indicators of stress, poor sleep, hard training and illness. It moves before you feel it.",
        steps: [
            "Apple Watch measures the gaps between heartbeats several times a day, mostly while you are still or asleep.",
            "The app takes each day's readings and averages them into one number.",
            "The chart shows each day as a dot, the 7-day average as a line, and a shaded band for your normal range (your 30-day average ± one typical variation)."
        ],
        example: "Your HRV normally sits between 45 and 65 ms. A reading of 38 for three days in a row is a clear signal.",
        reading: "Judge it by the 7-day line against the shaded band, not by single days. One low reading means little. Several days below the band suggest fatigue or illness. Everyone's HRV is different, so never compare yours to someone else's.",
        limits: "Alcohol, late meals, stress, illness and poor sleep all lower it, so it tells you something changed, not what. Apple Watch reports SDNN, which is not the same as the rMSSD measure used by most sports products."
    )

    static let restingHeartRate = Explainer(
        title: "Resting heart rate",
        what: "How fast your heart beats when you are completely at rest, in beats per minute. It's taken from your calmest periods of the day.",
        why: "A lower resting heart rate usually means a fitter, more efficient heart. Day to day, a rise above your normal is one of the simplest signs of fatigue, dehydration, illness or poor sleep.",
        steps: [
            "Apple Watch works out one resting value per day from your quietest, stillest stretches.",
            "The chart shows your daily values as dots, a 7-day average line and the shaded normal range."
        ],
        example: "If you normally rest at 54 bpm and it creeps to 60 for several days, your body is likely under extra strain.",
        reading: "Lower is generally better, but compare with yourself. A 7-day line rising above your normal range often shows up a day or two before you feel run down.",
        limits: "Caffeine, heat, alcohol and stress raise it temporarily. Fitness improvements lower it slowly over months."
    )

    static let breathingRate = Explainer(
        title: "Breathing rate",
        what: "How many breaths you take per minute during sleep, measured by your Watch.",
        why: "It is normally extremely steady for a given person, so a clear rise is one of the earliest signs of illness such as a cold or flu, and a marker of fatigue.",
        steps: [
            "The Watch estimates breathing rate overnight from tiny movements of your wrist.",
            "The chart compares each day with your normal range."
        ],
        example: "A person who always breathes 14 times per minute at night suddenly reading 17 for two nights should pay attention.",
        reading: "A steady line inside the band is normal. A clear rise out of the band is worth noticing, especially together with a higher resting heart rate and lower HRV.",
        limits: "Only measured while you sleep with the Watch on, and it can vary with altitude and nasal congestion."
    )

    static let sleepDuration = Explainer(
        title: "Sleep duration",
        what: "How long you were actually asleep each night, not how long you were in bed. Time awake during the night is excluded.",
        why: "Sleep is when your body repairs muscle, consolidates memory and resets hormones. Consistently short sleep undermines nearly everything else the app measures.",
        steps: [
            "Apple Health combines the sleep stages recorded by your Watch (core, deep and REM) into total time asleep.",
            "Each night is counted on the morning you wake up.",
            "On longer ranges, the bars show the average per night for each week or month.",
            "The grey bar on the left is your longer-term average, for comparison."
        ],
        example: "In bed 11:00pm to 6:45am with 25 minutes awake is about 7h 20m asleep.",
        reading: "Most adults do best with 7–9 hours, but your personal need is shown on the Sleep page. Regular bedtimes matter as much as the total.",
        limits: "Watches estimate sleep from movement and heart rate, so lying still awake can be counted as sleep, and short awakenings are missed."
    )

    static let steps = Explainer(
        title: "Steps",
        what: "The number of steps you take each day, counted by your iPhone and Apple Watch.",
        why: "It's the simplest measure of everyday movement, and higher daily step counts are linked with lower risk of early death in many large studies, with most of the benefit reached around 7,000–10,000.",
        steps: [
            "Health merges steps from your iPhone and Watch without double-counting.",
            "The bars show each day's total. On longer ranges, they show the average per day for each week or month."
        ],
        example: "A quiet day at a desk might be 4,000 steps, and a day with a long walk 12,000.",
        reading: "There is no magic number. Look for a steady weekly pattern and watch for sudden drops, which often accompany illness or low motivation.",
        limits: "Steps ignore intensity, cycling and lifting. A hard gym day can have few steps."
    )

    static let calories = Explainer(
        title: "Calories eaten",
        what: "The energy in the food and drink you've logged each day, in kilocalories.",
        why: "Body weight follows energy balance over time. Seeing your real intake against your target is the most direct lever for cutting, maintaining or building.",
        steps: [
            "Everything you log in the app or in Yazio is saved to Apple Health and added up by day.",
            "The green line is your calorie target, based on your maintenance calories and your goal."
        ],
        example: "A 2,400 kcal target with a day at 2,150 leaves 250 kcal under.",
        reading: "Look at the week, not single days. One high day is absorbed by the rest of the week.",
        limits: "Only as accurate as your logging. Restaurant meals and cooking oils are the usual gaps."
    )

    static let protein = Explainer(
        title: "Protein",
        what: "The grams of protein you eat each day.",
        why: "Protein supplies the building blocks for muscle repair. Enough of it protects muscle while cutting and helps growth while building.",
        steps: [
            "Protein from everything you log is added up per day.",
            "Your target comes from your body weight and goal.",
            "Bars that reach the green line hit your target."
        ],
        example: "An 80 kg person on a muscle-gain goal might aim for around 130–160 g a day.",
        reading: "Hitting the target most days matters more than perfection on any one day.",
        limits: "Protein from labels and databases has some error, and not all protein is equally well absorbed."
    )

    static let bodyWeight = Explainer(
        title: "Body weight and trend weight",
        what: "Your scale readings, plus a smoothed 'trend weight' that shows where your weight is really heading.",
        why: "Your weight can swing by 1–2 kg in a day from water, salt, food volume and hormones. The trend removes that noise so you can see real change.",
        steps: [
            "Each weigh-in is a dot.",
            "The trend line is a weighted average of recent readings, with newer readings counting more.",
            "It fills gaps between weigh-ins."
        ],
        example: "Readings of 80.4, 81.2, 80.1 and 80.6 kg produce a trend line at about 80.5 kg.",
        reading: "Read the line, not the dots. A steady slope over 2–3 weeks is real change.",
        limits: "Weigh at a similar time under similar conditions for the cleanest trend."
    )

    static let bodyFat = Explainer(
        title: "Body fat",
        what: "The percentage of your body weight that is fat, from a smart scale.",
        why: "It tells you what the scale's weight is made of, which matters more than the weight itself when gaining muscle or losing fat.",
        steps: [
            "Smart scales pass a small electrical current through the body and estimate composition from how it flows.",
            "The app plots each reading and a trend line."
        ],
        example: "Weight steady while body fat drops from 20% to 18% means you swapped fat for lean mass.",
        reading: "Follow the trend line. Single readings are noisy and swing with hydration.",
        limits: "Home scales can be off by several percentage points in absolute terms. Only compare readings from the same scale under similar conditions."
    )

    static let compositionSplit = Explainer(
        title: "Lean and fat mass",
        what: "Each weigh-in that includes body fat, split into lean mass (muscle, bone, organs, water) and fat mass, in kilograms.",
        why: "It shows what is actually changing. A weight that goes up while lean mass rises and fat stays flat is a successful bulk.",
        steps: [
            "Fat mass is your weight multiplied by your body-fat percentage.",
            "Lean mass is what remains.",
            "In every bar, lean mass is the lower part and fat mass sits on top."
        ],
        example: "At 80 kg and 20% body fat, you have 16 kg of fat mass and 64 kg of lean mass.",
        reading: "Look at each part separately over weeks. Lean up and fat flat or down is the goal for most people.",
        limits: "Depends on the scale's body-fat estimate, which is noisy."
    )

    static let training = Explainer(
        title: "Training minutes",
        what: "Minutes of workouts per day, split into strength training and cardio. Rest days count as zero.",
        why: "It shows the balance and consistency of your training across weeks, which is what actually produces results.",
        steps: [
            "Workouts logged by your Watch, the app or other apps in Apple Health are added up per day.",
            "Each is classed as strength or cardio by its type."
        ],
        example: "A 60-minute lifting session and a 30-minute run in one day show as 60 strength and 30 cardio.",
        reading: "Consistent weeks matter more than any single big day.",
        limits: "Duration says nothing about how hard the session was. See day strain for that."
    )
}

// MARK: - The explainer sheet

/// The "How it works" button that opens a metric's full explanation.
struct HowItWorks: View {
    let explainer: Explainer
    @State private var showing = false

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                showing = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "info.circle")
                    Text("How it works")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accentDeep)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showing) {
            ExplainerSheet(explainer: explainer)
                .presentationDetents([.large])
        }
    }
}

/// A small ⓘ for a card's header corner.
struct InfoButton: View {
    let explainer: Explainer
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "About \(explainer.title)"))
        .sheet(isPresented: $showing) {
            ExplainerSheet(explainer: explainer)
                .presentationDetents([.large])
        }
    }
}

struct ExplainerSheet: View {
    let explainer: Explainer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(LocalizedStringKey(explainer.what))
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    section("Why it matters", explainer.why)

                    VStack(alignment: .leading, spacing: 12) {
                        heading("How it's worked out")
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(explainer.steps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 12, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.accent)
                                        .frame(width: 24, height: 24)
                                        .background(Theme.accent.opacity(0.12), in: Circle())
                                    Text(LocalizedStringKey(step))
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineSpacing(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .card(padding: 16)
                    }

                    if let example = explainer.example {
                        VStack(alignment: .leading, spacing: 8) {
                            heading("An example")
                            Text(LocalizedStringKey(example))
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.accent.opacity(0.07),
                                            in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                        }
                    }

                    section("How to read your number", explainer.reading)
                    section("Good to know", explainer.limits)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(LocalizedStringKey(explainer.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func heading(_ text: String) -> some View {
        Text(LocalizedStringKey(text))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            heading(title)
            Text(LocalizedStringKey(body))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

import Foundation

/// Assembles the system prompt and user message from a natural language query
/// and a HealthDataBundle. Handles context window budget management.
struct PromptBuilder {

    // MARK: - System Prompt

    /// Returns the system prompt for the given expertise level.
    /// On-device models (Apple Foundation Model, 4 096-token context) get a compact
    /// ~800-char prompt so the total prompt (system + user data) stays well within
    /// their context window. Cloud models receive the full detailed prompt.
    static func systemPrompt(level: HealthExpertiseLevel = .intermediate, isOnDevice: Bool = false) -> String {
        if isOnDevice {
            return compactSystemPrompt(level: level)
        }
        return baseSystemPrompt + "\n\n" + expertiseBlock(for: level)
    }

    // MARK: - Compact System Prompt (on-device only)

    /// Minimal system prompt for on-device Apple Intelligence models.
    /// Each expertise level gets a structurally DIFFERENT prompt — different sections,
    /// different depth expectations, and different language rules — so the model
    /// cannot produce the same output regardless of level.
    private static func compactSystemPrompt(level: HealthExpertiseLevel) -> String {
        switch level {
        case .novice:
            return """
            You are HealthLens, a friendly health guide. The user is NEW to health tracking.

            CRITICAL RULES — follow every one:
            1. Use ONLY everyday language. ZERO jargon. If you must name a metric (e.g. HRV), explain it in one simple analogy first.
            2. Focus on 2–3 most important findings ONLY — do not overwhelm.
            3. For each finding: say what it measures in plain words, whether the number is GOOD or NEEDS ATTENTION, and why in one sentence.
            4. Frame everything positively — celebrate wins, frame improvements as easy opportunities.
            5. Give exactly 3 SIMPLE actions — each doable in under 30 min, no equipment needed.
            6. Only use data in the tables below. Quote actual numbers.
            7. Today's data is partial — do NOT flag it as a problem.

            Respond using ONLY these sections (no others):
            ## What Your Data Shows
            2–3 warm, friendly sentences summarising the answer. Start with something positive.
            ## Key Points
            2–3 bullet points. Each: plain-English metric name → their value → Good ✓ or Needs attention → one-sentence why.
            ## 3 Simple Actions This Week
            Exactly 3 beginner-friendly, specific steps anyone can do.
            ## 🎓 One Thing to Know
            One surprising or motivating health fact linked to their data, explained simply.
            ## Questions You Might Have
            2 simple follow-up questions.
            """

        case .intermediate:
            return """
            You are HealthLens, a health analytics AI for an engaged tracker.

            CRITICAL RULES — follow every one:
            1. Use standard health/fitness terms; define each on first use.
            2. Cover EVERY metric that has data — state value, healthy range, trend direction.
            3. Identify cross-system links (e.g. poor sleep → lower next-day HRV).
            4. Show trends: recent 7-day average vs full-period average.
            5. Give 4–5 specific, evidence-based recommendations with measurable numerical targets.
            6. Only use data in the tables. Quote specific numbers and dates.
            7. Today's data is partial — do NOT flag it as anomalous.

            Respond using ONLY these sections (no others):
            ## Summary
            2–3 sentences with specific numbers directly answering the question.
            ## Key Findings
            Bullet points covering EVERY metric with data — values, trends, ranges, week-vs-period comparison.
            ## Cross-System Patterns
            How the different metrics interact and what they reveal together.
            ## Recommendations
            4–5 specific, evidence-based steps with measurable targets and timeframes.
            ## 📈 Advanced Insight
            One deeper principle connecting their data to a broader health concept.
            ## Suggested Follow-Up Questions
            3 questions.
            """

        case .expert:
            return """
            You are HealthLens, a clinical health AI for a physiology-literate expert user.

            CRITICAL RULES — follow every one:
            1. Use full clinical and scientific terminology — NO simplification.
            2. Analyse ALL metrics with data: exact value, reference range, trend, clinical significance.
            3. Lead with cross-variable correlations and physiological mechanisms.
            4. Flag all anomalies, outliers, and non-obvious correlations.
            5. Give precise protocol-level recommendations: loads, ratios, timing windows, durations, thresholds.
            6. Only use data in the tables. Never invent values.
            7. Today's data is partial/in-progress — note it as such without drawing premature conclusions.

            Respond using ONLY these sections (no others):
            ## Clinical Summary
            Direct answer referencing key biomarkers and clinical significance.
            ## Biomarker Analysis
            Each metric: exact value • reference range • trend direction • clinical significance.
            ## Cross-System Correlations
            Physiological mechanisms linking the biomarkers across systems.
            ## Protocol Recommendations
            Precise interventions with targets, timing windows, durations, and dose-response expectations.
            ## Monitoring Priorities
            Key metrics to track closely with specific threshold triggers for clinical concern.
            ## Suggested Follow-Up Questions
            3 advanced analytical questions.
            """
        }
    }

    // MARK: - Base System Prompt (model-neutral, level-independent)

    private static var baseSystemPrompt: String {
        """
        You are HealthLens, a personal health intelligence assistant. The user has shared their \
        Apple Health data with you. The actual records available depend entirely on what the user \
        tracks — some categories may have rich data while others may be empty or sparse.

        ## Core Mission
        Analyse the user's health data **holistically**. Health systems are deeply interconnected — \
        sleep quality affects HRV and next-day activity, resting heart rate correlates with \
        fitness trends and stress levels, nutrition drives energy and body composition, and so on. \
        Surface these cross-system relationships, not just narrow answers.

        ## Analysis Principles
        1. **Only use data that is present**: never invent or assume values for metrics not in the dataset.
        2. **Cross-system correlation first**: identify which other available data categories are \
           relevant before answering the specific question.
        3. **Trend > single values**: compare 7-day vs 30-day averages, identify inflection points \
           and week-on-week changes.
        4. **Evidence-based specificity**: quote actual numbers from the data — "your average \
           resting HR dropped from 68 to 62 bpm over the past 3 weeks" not vague generalities.
        5. **Actionable recommendations**: for every finding, give at least one concrete, \
           measurable action the user can take this week.
        6. **Flag anomalies**: highlight outliers, sudden changes, or concerning patterns. Always \
           recommend consulting a healthcare professional for clinical concerns.

        ## Response Format
        - Use markdown: ## headings, **bold** for key metrics, bullet lists for action items
        - Lead with a direct 2–3 sentence answer to the user's question
        - Follow with "## Key Findings" covering the most important cross-system patterns
        - Add "## Recommendations" with specific, actionable steps
        - Do NOT include a "Data Gaps" section — the app selects only relevant metrics per query, so any category absent from the data tables below was simply not relevant to this question, NOT a gap in the user's data. Only mention a missing metric if the user explicitly asked about it AND it has zero rows in the provided tables.
        - End with "## Suggested Follow-Up Questions" (3–5 questions the user might find valuable)

        ## Unit Reference
        - Distances (daily totals): km | Short distances (step length, stride): m | Duration: minutes or hours | Heart rate: bpm
        - Energy: kcal | Sleep: hours | Blood pressure: mmHg | Weight: kg | Temperature: °C
        - VO₂ max: mL/kg·min | HRV (RMSSD): ms | SpO₂: % (0–100 scale) | Noise: dBASPL | Blood glucose: mg/dL

        ## Sleep Data Interpretation
        Sleep data is sourced from the app with the highest stage-sleep coverage per night \
        (Apple Watch, Oura, AutoSleep, etc.). The source is noted in the Sleep table. \
        Apple Watch records brief micro-awakenings throughout the night, so its 'Awake' \
        column is typically higher than third-party apps. Do NOT conclude poor sleep quality \
        from high Apple Watch Awake time alone. "Total Asleep" (Core + Deep + REM) is the \
        most comparable figure across sources. If a user says their sleep app shows different \
        numbers, explain the source difference rather than contradicting them.

        ## Heart Metrics — Sensor Context
        - **Heart Rate (HR)**: Apple Watch samples every few seconds during workouts, \
          every few minutes at rest. Outlier spikes (>180 bpm at rest) are usually motion \
          artifacts — note them as artifacts, not cardiac events.
        - **Resting Heart Rate (RHR)**: Apple Watch proprietary algorithm (lowest 5-min \
          average over any quiet hour). Range: 40–100 bpm; athletes 40–60. Lower is better. \
          Trending down week-over-week = improving fitness or recovery.
        - **Walking Heart Rate Average**: Average HR during relaxed walking. Target <100 bpm; \
          lower = better aerobic fitness. Elevated walking HR often mirrors a high RHR.
        - **HRV (reported as SDNN, actually RMSSD)**: Apple Watch measures RMSSD from 5-second \
          windows during sleep — NOT the clinical 24-hour SDNN standard. Typical range \
          20–105 ms; higher = better autonomic balance. Acute drops (>20 % below 30-day avg) \
          indicate stress, illness, overtraining, or alcohol. Interpret trends, not single values.
        - **VO₂ Max**: Apple Watch *estimate* from GPS outdoor walks/runs (not a lab test). \
          Typically underestimates actual VO₂ max by 10–15 %. Affected by terrain, wind, and \
          heat. Age/sex-based fitness tiers: Poor <25, Fair 25–33, Good 34–42, Excellent >43 \
          (mL/kg/min for adults 30–39; adjust for age). Trends matter more than absolute value.
        - **Cardio Recovery (1-min)**: HR drop in the first minute post-exercise. \
          <12 bpm drop = potentially concerning; >20 bpm = good fitness. If data is sparse, \
          note the user needs regular aerobic workouts to populate this metric.
        - **AFib Burden**: Percentage of time in atrial fibrillation over the measurement period. \
          ANY non-zero value warrants prompt medical consultation — always flag this and recommend \
          seeing a cardiologist. This is a clinically significant metric, not a lifestyle metric.
        - **ECG Classification**: Apple Watch records a single Lead I trace (30 s). \
          Classifications: Sinus Rhythm, Atrial Fibrillation, High/Low HR (inconclusive), \
          Poor Reading, Inconclusive. NOT a diagnostic ECG — recommend cardiology for any \
          AFib or repeated inconclusive readings.
        - **Peripheral Perfusion Index**: Ratio of pulsatile to non-pulsatile blood flow at \
          the wrist. Highly variable; useful as a trend indicator, not an absolute value.
        - **Heart Rate Events** (High/Low/Irregular): Triggered alerts from Apple Watch, \
          not continuous data. Each row is one event. Note count and recurrence; isolated \
          events are common; repeated events need follow-up.

        ## Body Metrics — Sensor Context
        - **Wrist Temperature (Apple Sleeping Wrist Temp)**: This value is the *deviation* \
          from the user's personal baseline in °C, NOT actual body temperature. \
          Negative = below baseline (post-illness recovery, low-stress night); \
          positive = above baseline (illness onset, ovulation, alcohol, hot environment). \
          A value of -0.3 means 0.3 °C below their typical baseline. Interpret the sign and \
          magnitude — do not report it as a body temperature reading.
        - **Electrodermal Activity (EDA)**: Galvanic skin response measured by Apple Watch \
          Ultra in Siemens (S). Reflects sympathetic nervous system activation. Highly \
          variable; interpret as a trend across weeks, not individual data points.
        - **Weight / BMI**: May come from smart scales (Withings, Renpho, etc.) or manual \
          entry. Multiple connected scales will each write — HealthKit statistics sum selects \
          the latest value per day (average), not a sum. BMI is a blunt screening tool; \
          pair with body fat % and lean mass for a fuller picture.
        - **Body Fat % / Lean Mass**: Typically from bioimpedance scales or manual entry. \
          Bioimpedance accuracy varies with hydration. Trends over weeks are meaningful; \
          day-to-day variation is noise.

        ## Vitals — Sensor Context
        - **Blood Oxygen (SpO₂)**: Apple Watch takes periodic background spot checks, NOT \
          continuous monitoring. Normal ≥95 %. Readings of 90–94 % are frequently motion \
          artifacts, especially on cold skin or darker skin tones. Sustained readings <95 % \
          during sleep or rest warrant medical evaluation. Do not alarm the user over a single \
          low reading.
        - **Respiratory Rate**: Estimated during sleep from wrist micro-movements and PPG patterns. \
          Normal adults: 12–20 breaths/min. Elevated rate (>20) sustained over multiple nights \
          may indicate respiratory issues, high stress, or illness.
        - **Blood Pressure (Systolic/Diastolic)**: From connected cuffs (Withings, Omron, \
          Qardio) or manual entry. Normal: <120/80 mmHg. Elevated: 120–129/<80. Hypertension \
          Stage 1: 130–139/80–89. Stage 2: ≥140/≥90. Isolated readings fluctuate; trends \
          across ≥10 measurements are clinically meaningful.
        - **Lung Function (FVC / FEV1 / Peak Flow)**: From connected spirometers or manual \
          entry. FEV1/FVC <0.70 suggests an obstructive pattern (asthma, COPD). Interpret \
          alongside symptoms; these are not screening tools.
        - **Body Temperature**: Manual entry or smart thermometer. Apple Watch does NOT record \
          core body temperature. Normal oral range: 36.1–37.2 °C.
        - **Blood Alcohol Content**: Manual log only. Legal driving limit: 0.08 % in most \
          jurisdictions.
        - **UV Exposure**: Manual logs or rare connected devices in standard erythemal doses \
          (SED). >1 SED = risk of sunburn for fair skin.

        ## Activity — Sensor Context
        - **Step Count**: HealthKit statistics API deduplicates overlapping iPhone + Apple Watch \
          step counts automatically (preferred source per time interval). No double-counting. \
          Normal goal: 7,000–10,000 steps/day. Display as whole numbers — a decimal step count \
          is an artifact of daily aggregation, always round.
        - **Active / Basal Energy**: Apple Watch estimates, ±10–30 % accuracy vs metabolic \
          testing. Active = above-resting energy. Basal = estimated resting metabolic rate \
          from anthropometrics. Together = estimated TDEE. Use for trend analysis, not precise \
          calorie accounting.
        - **Walking Steadiness**: iPhone-only (accelerometer-based gait analysis). \
          Classifications: OK, Low, Very Low. Decreases with age, recent injury, medication \
          changes, or neurological changes. A shift from OK to Low over weeks is a meaningful signal.
        - **Running Metrics** (Power, Ground Contact Time, Stride Length, Vertical Oscillation): \
          Apple Watch Ultra or paired accessory. Running economy benchmarks: ground contact \
          time <250 ms (elite) to <300 ms (recreational); vertical oscillation <5 cm = good \
          efficiency; stride length increases with speed. Interpret in context of the user's pace.
        - **Six-Minute Walk Test Distance**: Formal clinical test (recorded manually or via \
          third-party app). Age/sex norms: 50-year-old male ~550 m; female ~500 m. Below \
          300 m suggests significant functional limitation.
        - **Exercise Time**: Minutes where HR entered the exercise zone (Apple Watch). \
          Goal: 30 min/day moderate activity. Trends relative to the 30-min daily goal.
        - **Stand Hours / Stand Time**: Apple Watch metric. 12+ stand hours/day = met goal. \
          Prolonged sedentary blocks (4+ h) increase cardiometabolic risk.

        ## Nutrition — Multi-Source Caveat & Full Coverage Requirement
        Nutrition data is the SUM of all logged entries across all apps (MyFitnessPal, Lose It, \
        Cronometer, Apple Health, etc.). If the user logs the same meal in two apps, HealthKit \
        WILL double-count it. Incomplete logging is far more common than double-logging; if \
        daily totals look low or irregular, note that missed logs are likely. Dietary data \
        reflects what was logged, not total actual intake.

        **IMPORTANT — analyse EVERY nutrient that has recorded values, not just headline macros.** \
        Structure nutrition analysis in groups (skip any group with zero data):
        1. Energy balance: calories vs estimated expenditure
        2. Macronutrients: protein (~0.8–1.2 g/kg body weight goal), carbohydrates, total fat, \
           saturated/unsaturated split, fibre (≥25 g women / ≥38 g men), sugar, cholesterol
        3. Hydration & stimulants: water (2–2.5 L/day), caffeine, alcohol
        4. Vitamins (if logged): fat-soluble (A, D, E, K) and water-soluble (C, B1/B2/B3/B5/B6/B7/B9/B12)
        5. Minerals (if logged): calcium, iron, magnesium, potassium, sodium (<2 300 mg/day), zinc, \
           chromium, copper, iodine, manganese, molybdenum, phosphorus, selenium, chloride
        Quote actual daily totals and compare to standard dietary reference intakes where relevant. \
        Do NOT skip any nutrient that has non-zero data in the tables.

        ## Mindfulness & Wellness Events
        Mindful sessions are summed across all apps (Calm, Headspace, Breathe, third-party). \
        Summing is correct — multiple sessions from different apps in a day are all valid. \
        Handwashing and toothbrushing events are Apple Watch-detected behaviours; gaps simply \
        mean the Watch was not worn or the gesture was not detected.

        ## Labs (Blood Glucose)
        Blood glucose may come from manual finger-stick logs, BGM apps, or CGM integrations \
        (Dexterity, Libre 3). CGM values are interstitial glucose with a 10–15 min lag behind \
        actual blood glucose. Normal fasting: 3.9–5.5 mmol/L (70–99 mg/dL); \
        pre-diabetic fasting: 5.6–6.9 mmol/L; diabetic: ≥7.0 mmol/L. \
        Post-meal spikes >10 mmol/L (180 mg/dL) lasting >2 h warrant attention.

        ## Environment (Noise Exposure)
        Environmental audio exposure is a weekly dBASPL average from Apple Watch microphone. \
        Headphone exposure is from AirPods/connected headphones. Occupational safe limit: \
        85 dBASPL for 8 h/day. Recreational noise risk begins around 100 dBASPL (concerts). \
        Weekly averages smooth out peaks — a 75 dBASPL weekly average could still include \
        brief exposures >100 dBASPL.

        ## Temporal Interpretation
        - Each user message includes a **Temporal Context** section with the current local date, time, and timezone.
        - **Today is always an in-progress / partial day** — its data is incomplete and accumulating. \
          Never flag today's low step count, low calories, or short sleep as a health anomaly; \
          simply note it is partial. Do NOT draw conclusions from today's partial totals.
        - When the user says **"this week"** or **"last 7 days"**, analyse the 7 most recent \
          **complete** days (yesterday back 6 more days). Present today's partial figures \
          separately as "Today so far" only if directly relevant.
        - When the user says **"this month"** or **"last 30 days"**, analyse the last 30 complete days.
        - Always reference dates by their local calendar date as shown in the data tables \
          (the data is already in the user's local timezone).
        - If today's data appears much lower than average for a metric (steps, calories, etc.), \
          acknowledge it is a partial day rather than labelling it as a drop or anomaly.

        ## Important Caveats
        - This analysis is informational only — NOT medical advice or diagnosis
        - Never mention data gaps or missing metrics unless the user explicitly asked for that specific metric; the app selects only relevant data for each query, so absence from the bundle does not mean the user lacks that data
        - Respect privacy: do not echo back sensitive identifiers in your response
        """
    }

    // MARK: - Expertise Level Block

    private static func expertiseBlock(for level: HealthExpertiseLevel) -> String {
        switch level {
        case .novice:
            return """
            ## Your Audience: Novice (Health Beginner)
            The user is new to health tracking and may not understand medical or fitness terminology.

            **Communication rules:**
            - Use simple, everyday language throughout. No jargon — or if you must use a term (e.g. HRV), \
              explain it in one friendly sentence using an analogy first.
            - For each metric you mention, briefly say what it measures before interpreting it \
              (e.g. "Resting heart rate is how fast your heart beats when you're completely relaxed — \
              lower is generally better for most people").
            - Focus on the **2–3 most impactful findings** only. Do not overwhelm with detail.
            - Frame everything constructively: celebrate any positive trend, and frame areas for \
              improvement as exciting opportunities rather than failures.
            - Provide exactly **3 simple, beginner-friendly actions** for this week — each should be \
              achievable in under 30 minutes and require no special equipment.
            - End every response with a **"🎓 Level-Up Tip"** section: one sentence that introduces \
              a slightly more advanced concept linked to the findings, sparking curiosity about becoming \
              an Intermediate-level tracker (e.g. "Once you're hitting your step goal consistently, \
              you might enjoy exploring how your resting heart rate changes as your fitness improves").
            """

        case .intermediate:
            return """
            ## Your Audience: Intermediate (Engaged Health Tracker)
            The user understands basic health metrics (steps, sleep stages, heart rate, calories) \
            and tracks their health regularly.

            **Communication rules:**
            - Use standard health and fitness terminology; define technical terms on **first use** \
              (e.g. "HRV — heart rate variability, a measure of autonomic nervous system balance").
            - Explain **cross-system relationships**: how sleep quality affects next-day HRV, how \
              resting HR reflects cumulative fitness trends, how nutrition timing impacts energy levels.
            - Provide **4–5 specific, evidence-based recommendations** with measurable targets \
              (e.g. "Aim for 7–9 hours of sleep with ≥20 % REM — your current average is X hours").
            - Include benchmark comparisons where relevant \
              (e.g. "Your resting HR of 62 bpm sits in the 'good' range for your age group").
            - Show trend analysis: compare recent 7-day vs 30-day averages, highlight week-on-week changes.
            - End with a **"📈 Advanced Insight"** section: one concept that bridges toward expert-level \
              understanding (e.g. an introduction to HRV coaching zones, periodisation, or micronutrient \
              interactions).
            """

        case .expert:
            return """
            ## Your Audience: Expert (Health & Performance Optimiser)
            The user has deep knowledge of physiology, performance optimisation, and health biomarkers. \
            They track and interpret their own data independently.

            **Communication rules:**
            - Use full clinical and scientific terminology without simplification or definitions.
            - Lead with **cross-variable correlations and multi-system analysis**: autonomic balance, \
              metabolic efficiency, recovery capacity, hormetic stress adaptations, nutrient partitioning, etc.
            - Reference physiological mechanisms where they clarify the data \
              (e.g. "The 18 % HRV suppression coinciding with elevated resting HR and shortened REM \
              suggests sustained sympathetic dominance — likely cumulative training load or sub-clinical illness onset").
            - Provide **precise, protocol-level recommendations**: specific loads, recovery ratios, \
              timing windows, target ranges, and duration of interventions.
            - Highlight statistically notable patterns, outliers, or non-obvious correlations.
            - No need for beginner tips or analogies — focus entirely on advanced optimisation insights \
              and nuanced interpretation.
            """
        }
    }

    // MARK: - Temporal Context

    /// Builds a concise temporal context block for injection into every prompt.
    /// This tells the AI the current local date/time and how to interpret "today",
    /// "this week", etc. — critical for correct date attribution in any timezone.
    static func temporalContext() -> String {
        let now = Date()
        let cal = Calendar.current
        let tz  = TimeZone.current

        // Human-readable timestamp in local timezone.
        let dtFmt = DateFormatter()
        dtFmt.dateStyle = .full
        dtFmt.timeStyle = .short
        dtFmt.timeZone  = tz
        let formattedNow = dtFmt.string(from: now)

        // UTC offset string (e.g. "UTC+1" or "UTC+5:30").
        let offsetSec  = tz.secondsFromGMT(for: now)
        let offsetH    = offsetSec / 3600
        let offsetM    = abs((offsetSec % 3600) / 60)
        let tzAbbr     = tz.abbreviation(for: now) ?? "UTC"
        let offsetStr: String
        if offsetM == 0 {
            offsetStr = offsetH >= 0 ? "UTC+\(offsetH)" : "UTC\(offsetH)"
        } else {
            offsetStr = offsetH >= 0
                ? "UTC+\(offsetH):\(String(format: "%02d", offsetM))"
                : "UTC\(offsetH):\(String(format: "%02d", offsetM))"
        }

        // Date strings in local timezone.
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.timeZone   = tz
        let todayStr     = dateFmt.string(from: now)
        let yesterday    = cal.date(byAdding: .day, value: -1, to: now)!
        let yesterdayStr = dateFmt.string(from: yesterday)
        let weekStart    = cal.date(byAdding: .day, value: -7, to: now)!
        let weekStartStr = dateFmt.string(from: weekStart)

        return """
        ## Temporal Context
        Current date and time: \(formattedNow) [\(tzAbbr), \(offsetStr)]
        Today's date: \(todayStr) — **in-progress / partial day** (data is still accumulating).
        "This week" = last 7 complete days: \(weekStartStr) → \(yesterdayStr).
        All dates in the health data below are already in the user's local timezone (\(tzAbbr)).
        """
    }

    /// Builds an environmental context block from weather/location data.
    /// Only the human-readable city name, country, season, and weather description
    /// are included — raw coordinates are never sent to AI providers.
    static func environmentalContext(from weather: WeatherContext?) -> String {
        guard let w = weather else { return "" }

        var lines: [String] = []

        // Location / region
        if !w.city.isEmpty && !w.country.isEmpty {
            lines.append("Location: \(w.city), \(w.country)")
        } else if !w.country.isEmpty {
            lines.append("Region: \(w.country)")
        }

        lines.append("Season: \(w.season)")

        // Current weather (only when we actually fetched it)
        if w.hasWeatherData {
            let temp = String(format: "%.0f", w.temperatureC)
            let feels = String(format: "%.0f", w.feelsLikeC)
            var weatherLine = "Current weather: \(temp)°C (feels like \(feels)°C), \(w.condition)"
            if w.humidity > 0 { weatherLine += ", Humidity \(w.humidity)%" }
            if w.windSpeedKmh > 0 { weatherLine += ", Wind \(String(format: "%.0f", w.windSpeedKmh)) km/h" }
            lines.append(weatherLine)
        }

        guard !lines.isEmpty else { return "" }

        let block = lines.joined(separator: "\n")
        return """
        ## Environmental Context
        \(block)
        Note: Factor in environmental conditions where relevant — hot/humid conditions \
        elevate resting HR, perceived exertion, and recovery time; cold weather can \
        reduce outdoor activity and suppress vitamin D synthesis; winter is associated \
        with seasonal mood changes and reduced activity; high heat increases hydration needs. \
        Tailor recommendations to the user's current season and climate.
        """
    }

    // MARK: - User Message

    /// Builds the full user message for a fresh (non-follow-up) query.
    /// Health data is formatted as **markdown tables** — far more readable for LLMs
    /// than raw compact JSON. Each metric gets its own table grouped by category,
    /// making it easy for the model to directly reference specific values and dates.
    ///
    /// - Parameters:
    ///   - level: Expertise level — drives analysis depth and the Required Coverage block.
    ///   - weatherContext: Optional weather/region context to enrich AI recommendations.
    ///   - conversationHistory: Previous (query, response) pairs in the current conversation.
    static func buildMessage(
        query: String,
        bundle: HealthDataBundle,
        maxCharacters: Int = 80_000,
        level: HealthExpertiseLevel = .intermediate,
        weatherContext: WeatherContext? = nil,
        conversationHistory: [(query: String, response: String)] = []
    ) throws -> String {
        // Metric index: compact one-liner per category — always prepended.
        let metricIndex = buildMetricIndex(from: bundle)

        // Explicit data summary so the AI knows exactly what it received.
        let dataSummary = buildDataSummary(from: bundle)

        // Category-specific analysis requirements: tells the AI exactly which metrics to cover.
        let analysisFocus = buildAnalysisFocus(from: bundle, level: level)

        // Environmental context block (weather / season / region)
        let envContext = environmentalContext(from: weatherContext)

        // Build readable markdown tables — much smaller than JSON and directly
        // parseable by LLMs. A typical 30-day dataset is ~20K chars vs ~150K JSON.
        let healthMarkdown = buildMarkdownTables(from: bundle)

        // Account for history snippets (capped at 600 chars per response) + overhead.
        let historyChars = conversationHistory.reduce(0) {
            $0 + $1.query.count + min($1.response.count, 600)
        }
        let totalChars = healthMarkdown.count + metricIndex.count + dataSummary.count
                       + analysisFocus.count + envContext.count + historyChars + query.count + 2_000

        if totalChars <= maxCharacters {
            return buildMessageText(
                query: query, healthData: healthMarkdown,
                metricIndex: metricIndex, dataSummary: dataSummary,
                analysisFocus: analysisFocus,
                envContext: envContext,
                conversationHistory: conversationHistory
            )
        }

        // Over budget — truncate by keeping only the most recent days per metric.
        let dataCharBudget = max(2_000, maxCharacters - historyChars - query.count
                                      - metricIndex.count - dataSummary.count
                                      - analysisFocus.count - envContext.count - 2_000)
        let truncated = truncateBundle(bundle, targetCharacters: dataCharBudget)
        let truncatedMarkdown = buildMarkdownTables(from: truncated)
        return buildMessageText(
            query: query, healthData: truncatedMarkdown,
            metricIndex: metricIndex, dataSummary: dataSummary,
            analysisFocus: analysisFocus,
            envContext: envContext,
            conversationHistory: conversationHistory,
            isTruncated: true
        )
    }

    // MARK: - Analysis Focus (per-category metric coverage)

    /// Returns a "## Required Coverage" block listing every metric the AI MUST analyse
    /// for each category that has data in the bundle. This is injected into the user
    /// message so it works for both on-device and cloud models, and ensures sleep queries
    /// always cover Core/Deep/REM/Awake, heart queries cover HRV/VO₂Max/AFib etc.
    private static func buildAnalysisFocus(from bundle: HealthDataBundle, level: HealthExpertiseLevel) -> String {
        let categories = Set(bundle.categories.filter { !$0.value.isEmpty }.keys)
        guard !categories.isEmpty else { return "" }

        var lines: [String] = []

        if categories.contains(HealthCategory.sleep.rawValue) {
            lines.append("**Sleep** — address ALL of these stages/metrics that have data:\n" +
                "  • Total sleep duration per night (Core + Deep + REM = Total Asleep)\n" +
                "  • Core sleep (light NREM) — hours and % of total\n" +
                "  • Deep sleep (slow-wave/SWS) — hours and %; healthy target ~15–20% of total\n" +
                "  • REM sleep — hours and %; healthy target ~20–25% of total\n" +
                "  • Awake time (note: Apple Watch records more awakenings than 3rd-party apps — this is normal)\n" +
                "  • Night-to-night consistency and any anomaly nights")
        }

        if categories.contains(HealthCategory.heart.rawValue) {
            lines.append("**Heart** — address ALL of these metrics that have data:\n" +
                "  • Resting Heart Rate (RHR) — trend and week-vs-period average\n" +
                "  • Heart Rate Variability (HRV/RMSSD) — trend; flag any acute drop >20% from baseline\n" +
                "  • Walking Heart Rate Average — cardiovascular fitness indicator\n" +
                "  • VO₂ Max estimate — current value and fitness tier for user's profile\n" +
                "  • Cardio Recovery (1-min post-exercise HR drop) — if available\n" +
                "  • AFib Burden — flag ANY non-zero value as requiring immediate medical attention\n" +
                "  • ECG recordings — summarise count, classifications (Sinus Rhythm / AFib / Inconclusive / Poor Reading) and avg HR per reading; flag ANY AFib classification or repeated inconclusive results for medical follow-up\n" +
                "  • Heart Rate Events (High/Low/Irregular) — count and pattern")
        }

        if categories.contains(HealthCategory.activity.rawValue) {
            lines.append("**Activity** — address ALL of these metrics that have data:\n" +
                "  • Daily step count vs 7,000–10,000/day goal\n" +
                "  • Active energy (kcal) vs basal energy — estimated TDEE\n" +
                "  • Exercise minutes vs 30 min/day goal\n" +
                "  • Stand hours vs ≥12/day goal\n" +
                "  • Distance walked/run\n" +
                "  • Workout sessions (type, duration, calories) if logged")
        }

        // When both heart AND activity data are present, explicitly ask for cardio cross-analysis.
        if categories.contains(HealthCategory.heart.rawValue) &&
           categories.contains(HealthCategory.activity.rawValue) {
            lines.append("**Cardio Fitness Cross-Analysis** — required when both Heart and Activity data are present:\n" +
                "  • Correlate weekly exercise minutes with VO₂ Max trend — is cardio fitness improving with training load?\n" +
                "  • Relate Resting Heart Rate trend to exercise frequency and intensity\n" +
                "  • Note whether Cardio Recovery (1-min post-exercise drop) is improving alongside training\n" +
                "  • Identify if activity gaps (low-exercise weeks) correspond to HRV drops or RHR spikes")
        }

        if categories.contains(HealthCategory.body.rawValue) {
            lines.append("**Body Composition** — address ALL of these that have data:\n" +
                "  • Weight trend (week-over-week change)\n" +
                "  • BMI — value and category (underweight/normal/overweight/obese)\n" +
                "  • Body fat % and lean mass trends (if logged)\n" +
                "  • Wrist temperature deviation — this is °C deviation from personal baseline, NOT body temperature")
        }

        if categories.contains(HealthCategory.nutrition.rawValue) {
            lines.append("**Nutrition** — address ALL of these that have data:\n" +
                "  • Calories logged vs estimated expenditure\n" +
                "  • Protein (g and g/kg body weight) — target 0.8–1.2 g/kg\n" +
                "  • Carbohydrates and fiber (target ≥25g women/≥38g men) and sugar breakdown\n" +
                "  • Total fat, saturated fat, unsaturated fat split\n" +
                "  • Water intake (target 2–2.5 L/day)\n" +
                "  • Caffeine and alcohol (if logged)\n" +
                "  • Any vitamins or minerals with notable values")
        }

        if categories.contains(HealthCategory.vitals.rawValue) {
            lines.append("**Vitals** — address ALL of these that have data:\n" +
                "  • Blood pressure trend — stage classification (normal <120/80, elevated 120–129/<80, hypertension ≥130/80)\n" +
                "  • Blood oxygen / SpO₂ — sustained readings <95% during rest warrant attention\n" +
                "  • Respiratory rate — normal range 12–20 breaths/min\n" +
                "  • Any other vitals logged")
        }

        if categories.contains(HealthCategory.mindfulness.rawValue) {
            lines.append("**Mindfulness** — address if data is present:\n" +
                "  • Total mindful minutes and session count\n" +
                "  • Apple Watch detected behaviours (handwashing, toothbrushing) if logged")
        }

        if categories.contains(HealthCategory.labs.rawValue) {
            lines.append("**Labs** — address ALL that have data:\n" +
                "  • Blood glucose values and trends (fasting normal: 3.9–5.5 mmol/L)\n" +
                "  • Flag any pre-diabetic (5.6–6.9 mmol/L) or diabetic (≥7.0) fasting values")
        }

        if lines.isEmpty { return "" }

        let depthNote: String
        switch level {
        case .novice:
            depthNote = "For each metric: briefly explain what it measures in plain words, whether their value is good or needs attention, and give ONE beginner-friendly action."
        case .intermediate:
            depthNote = "For each metric: state the exact value, compare to healthy range, describe trend direction, and note any cross-metric relationships."
        case .expert:
            depthNote = "For each metric: exact value with reference range, statistical trend, clinical significance, and physiological mechanism where relevant."
        }

        return """
        ## Required Coverage
        You MUST address every metric listed below that has data in the health tables. Do NOT skip any parameter.
        \(depthNote)

        \(lines.map { "• \($0)" }.joined(separator: "\n\n"))
        """
    }

    // MARK: - Markdown Table Builder

    /// Converts a HealthDataBundle into LLM-readable markdown tables, grouped by category.
    /// Sleep is aggregated into nightly summaries (Core/Deep/REM/Awake per night).
    /// Other metrics get their own `### Heading` and `| Date | Value |` table.
    static func buildMarkdownTables(from bundle: HealthDataBundle) -> String {
        var output = ""
        let categories = bundle.categories.sorted(by: { $0.key < $1.key })

        for (categoryName, records) in categories {
            guard !records.isEmpty else { continue }

            // Sleep: aggregate by "night of" date into a single summary table.
            if categoryName == HealthCategory.sleep.rawValue {
                output += buildSleepTable(from: records)
                continue
            }

            // Group records by displayName for a cleaner per-metric table.
            var byDisplay: [String: [SerializedHealthRecord]] = [:]
            for record in records {
                byDisplay[record.displayName, default: []].append(record)
            }

            output += "## \(categoryName.capitalized)\n\n"

            for (displayName, typeRecords) in byDisplay.sorted(by: { $0.key < $1.key }) {
                guard let first = typeRecords.first else { continue }
                let sorted = typeRecords.sorted { $0.date < $1.date }

                // ECG: include heart-rhythm classification column
                if first.typeIdentifier == "HKDataTypeIdentifierElectrocardiogram" {
                    output += "### \(displayName) (bpm avg)\n"
                    output += "| Date | Avg HR | Rhythm |\n|------|--------|--------|\n"
                    for r in sorted {
                        let cls = ecgClassificationName(Int(r.metadata?["classification"] ?? 0))
                        output += "| \(r.date) | \(fmtVal(r.value)) bpm | \(cls) |\n"
                    }
                    output += "\n"
                    continue
                }

                // Workouts: include calories column
                if first.typeIdentifier == "HKWorkoutTypeIdentifier" {
                    output += "### \(displayName)\n"
                    output += "| Date | Duration | Calories |\n|------|----------|----------|\n"
                    for r in sorted {
                        let cals = r.metadata?["calories"].map { "\(Int($0)) kcal" } ?? "–"
                        output += "| \(r.date) | \(fmtVal(r.value)) min | \(cals) |\n"
                    }
                    output += "\n"
                    continue
                }

                // Standard metrics
                let aggLabel: String
                switch first.aggregation {
                case "sum":      aggLabel = "daily total"
                case "average":  aggLabel = "daily avg"
                case "duration": aggLabel = "duration"
                default:         aggLabel = "value"
                }
                output += "### \(displayName) (\(first.unit), \(aggLabel))\n"
                output += "| Date | Value |\n|------|-------|\n"
                for r in sorted {
                    output += "| \(r.date) | \(fmtVal(r.value)) \(r.unit) |\n"
                }
                output += "\n"
            }
        }

        return output.isEmpty ? "(no health data recorded in this period)\n" : output
    }

    // MARK: - Sleep Night Aggregation

    /// Builds a nightly sleep summary table from raw stage records.
    /// All records must already be tagged with the "night of" date (done in HealthDataSerializer).
    /// One row per night showing Total Asleep, Core, Deep, REM, Awake, and In Bed durations.
    private static func buildSleepTable(from records: [SerializedHealthRecord]) -> String {
        struct NightTotals {
            var core: Double = 0
            var deep: Double = 0
            var rem: Double = 0
            var awake: Double = 0
            var inBed: Double = 0
            var unspecified: Double = 0   // "Asleep" (unclassified)
            var totalAsleep: Double { core + deep + rem + unspecified }
        }

        var nights: [String: NightTotals] = [:]
        var sources = Set<String>()
        for r in records {
            var n = nights[r.date, default: NightTotals()]
            switch r.displayName {
            case "Core Sleep":  n.core        += r.value
            case "Deep Sleep":  n.deep        += r.value
            case "REM Sleep":   n.rem         += r.value
            case "Awake":       n.awake       += r.value
            case "In Bed":      n.inBed       += r.value
            case "Asleep":      n.unspecified += r.value
            default: break
            }
            nights[r.date] = n
            sources.insert(r.source)
        }

        guard !nights.isEmpty else { return "" }

        var output = "## Sleep\n\n"
        output += "### Nightly Sleep Summary\n"
        output += "> Date = the evening the sleep began. All durations in hours.\n"
        output += "> Total Asleep = Core + Deep + REM (excludes Awake time).\n"

        // Surface the data source so the AI can contextualise discrepancies the user
        // might report when comparing to a third-party sleep app's numbers.
        if !sources.isEmpty {
            let srcNames = sources.sorted().map { friendlySourceName($0) }.joined(separator: ", ")
            output += "> Source: \(srcNames)\n"
            if sources.contains(where: { $0.hasPrefix("com.apple") }) {
                output += "> Note: Apple Watch records brief micro-awakenings; Awake time may appear higher than third-party apps report.\n"
            }
        }
        output += "\n"
        output += "| Night      | Total Asleep | Core  | Deep  | REM   | Awake | In Bed |\n"
        output += "|------------|-------------|-------|-------|-------|-------|--------|\n"

        for (night, n) in nights.sorted(by: { $0.key < $1.key }) {
            let core  = n.core  > 0 ? "\(fmtVal(n.core)) h"  : "–"
            let deep  = n.deep  > 0 ? "\(fmtVal(n.deep)) h"  : "–"
            let rem   = n.rem   > 0 ? "\(fmtVal(n.rem)) h"   : "–"
            let awake = n.awake > 0 ? "\(fmtVal(n.awake)) h" : "–"
            let inBed = n.inBed > 0 ? "\(fmtVal(n.inBed)) h" : "–"
            output += "| \(night) | **\(fmtVal(n.totalAsleep)) hrs** | \(core) | \(deep) | \(rem) | \(awake) | \(inBed) |\n"
        }
        output += "\n"
        return output
    }

    /// Converts a HealthKit bundle identifier to a short human-readable app name.
    private static func friendlySourceName(_ bundleID: String) -> String {
        switch true {
        case bundleID == "com.apple.health",
             bundleID == "com.apple.healthkit",
             bundleID.hasPrefix("com.apple.Health"):
            return "Apple Health/Watch"
        case bundleID.contains("oura"):       return "Oura"
        case bundleID.contains("autosleep"):  return "AutoSleep"
        case bundleID.contains("sleepwatch"): return "SleepWatch"
        case bundleID.contains("pillow"):     return "Pillow"
        default:
            // Strip reverse-DNS prefix: com.foo.BarApp → BarApp
            let parts = bundleID.split(separator: ".").dropFirst(2)
            return parts.first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? bundleID
        }
    }

    private static func fmtVal(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
    }

    private static func ecgClassificationName(_ raw: Int) -> String {
        switch raw {
        case 1: return "Sinus Rhythm"
        case 2: return "Atrial Fibrillation"
        case 3: return "High HR (inconclusive)"
        case 4: return "Low HR (inconclusive)"
        case 5: return "Poor Reading"
        case 6: return "Inconclusive"
        default: return "Not Set"
        }
    }

    // MARK: - Follow-up Message (no data re-send)

    /// Lightweight message for follow-up queries in an active conversation.
    /// Sends conversation history + metric index only — the full health bundle is
    /// deliberately omitted because the LLM already analyzed it in the prior exchange.
    /// Conversation history snippets are longer here (up to 2 000 chars per response)
    /// so the model has rich context from the prior analysis.
    static func buildFollowUpMessage(
        query: String,
        metricIndex: String,
        conversationHistory: [(query: String, response: String)]
    ) -> String {
        var message = ""

        if !conversationHistory.isEmpty {
            message += "## Conversation History\n"
            for (i, exchange) in conversationHistory.enumerated() {
                let snippet = exchange.response.count > 2_000
                    ? String(exchange.response.prefix(2_000)) + "…"
                    : exchange.response
                message += "**Q\(i + 1):** \(exchange.query)\n**A\(i + 1):** \(snippet)\n\n"
            }
        }

        message += """
        \(temporalContext())

        ## Follow-up Question
        \(query)

        ## Metrics Available in This Conversation
        \(metricIndex)

        ## Instructions
        This is a follow-up question in an ongoing health analysis conversation. \
        The complete health data was already shared and analyzed in the prior exchange(s) above. \
        Use the conversation history as your data context — do **not** ask for data you already have. \
        Answer concisely and directly, referencing specific metrics and trends from prior analysis. \
        Today's date is noted in the Temporal Context above — any data for that date is partial. \
        Only request a fresh data pull if the user explicitly asks about a time range or metric \
        not covered in the existing conversation.
        """

        return message
    }


    /// Compact one-liner per category listing every unique displayName present in the bundle.
    /// Public so QueryViewModel can pass it to buildFollowUpMessage without re-encoding data.
    static func buildMetricIndex(from bundle: HealthDataBundle) -> String {
        var lines = ["Metrics with recorded data:"]
        for (category, records) in bundle.categories.sorted(by: { $0.key < $1.key }) {
            var seen = Set<String>()
            let names = records.compactMap { r -> String? in
                guard !seen.contains(r.displayName) else { return nil }
                seen.insert(r.displayName)
                return r.displayName
            }
            if !names.isEmpty {
                lines.append("  • \(category): \(names.joined(separator: ", "))")
            }
        }
        if lines.count == 1 { lines.append("  (no data recorded in this period)") }
        return lines.joined(separator: "\n")
    }

    /// Short paragraph summarising record counts per category so the AI knows exactly
    /// how much data it received — prevents the model from claiming it "has no data"
    /// when data is present, or silently ignoring empty categories.
    static func buildDataSummary(from bundle: HealthDataBundle) -> String {
        let start = bundle.dateRangeStart.formatted(.dateTime.day().month().year())
        let end   = bundle.dateRangeEnd.formatted(.dateTime.day().month().year())
        let total = bundle.metadata.totalRecordCount

        var lines = ["Period: \(start) → \(end). Total records: \(total)."]
        let sorted = bundle.categories.sorted(by: { $0.key < $1.key })
        let withData    = sorted.filter { !$0.value.isEmpty }
        let withoutData = sorted.filter {  $0.value.isEmpty }

        if !withData.isEmpty {
            let parts = withData.map { "\($0.key) (\($0.value.count) records)" }
            lines.append("Categories WITH data: \(parts.joined(separator: ", ")).")
        }
        if !withoutData.isEmpty {
            let parts = withoutData.map(\.key)
            lines.append("Categories with NO data this period: \(parts.joined(separator: ", ")).")
        }
        return lines.joined(separator: " ")
    }

    private static func buildMessageText(
        query: String,
        healthData: String,
        metricIndex: String,
        dataSummary: String,
        analysisFocus: String = "",
        envContext: String = "",
        conversationHistory: [(query: String, response: String)] = [],
        isTruncated: Bool = false
    ) -> String {
        var message = ""

        // Prepend prior conversation exchanges so the LLM has full context.
        if !conversationHistory.isEmpty {
            message += "## Conversation History\n"
            for (i, exchange) in conversationHistory.enumerated() {
                let snippet = exchange.response.count > 2_000
                    ? String(exchange.response.prefix(2_000)) + "…"
                    : exchange.response
                message += "**Q\(i + 1):** \(exchange.query)\n**A\(i + 1):** \(snippet)\n\n"
            }
        }

        let focusBlock = analysisFocus.isEmpty ? "" : "\n\n\(analysisFocus)"
        let envBlock   = envContext.isEmpty    ? "" : "\n\n\(envContext)"

        message += """
        \(temporalContext())\(envBlock)

        ## User Question
        \(query)

        ## Data Availability Summary
        \(dataSummary)

        ## Available Metrics
        \(metricIndex)\(focusBlock)

        ## Instructions
        The health data tables below contain the user's ACTUAL records pulled from Apple HealthKit \
        for the period shown in the Data Availability Summary. Each table shows real measured values \
        for a specific metric. Dates are in YYYY-MM-DD format (user's local timezone — see Temporal Context). \
        You MUST reference specific numbers and dates from the tables in your response — \
        do NOT say you "cannot see" or "don't have access to" data that is present in the tables below. \
        Use ONLY data present in the tables; never invent or estimate values. \
        **IMPORTANT — NO DATA GAPS SECTION**: The app fetches only the categories relevant to the user's query. \
        Categories NOT present in the tables below were intentionally excluded because they were not relevant \
        to this query — they are NOT missing from the user's health data. \
        Do NOT mention nutrition, body composition, blood pressure, or any other absent category as a "data gap". \
        Do NOT include a "## Data Gaps" section at all. \
        The only exception: if the user explicitly asked about a specific metric and that exact metric has 0 rows \
        in the tables, then state "no [metric] readings were recorded in this period" once and move on. \
        If a specific sub-metric (e.g. Resting Heart Rate) has 0 rows but its category has other data, \
        say "no [metric] readings were recorded in this period" — do NOT pivot to analysing different metrics instead. \
        Today's date is noted in the Temporal Context above — treat that date's data as incomplete/partial.
        \(isTruncated ? "\nNote: Oldest records trimmed to fit context — most recent data is preserved. Reduce date range for full history." : "")

        ## Your Health Data
        \(healthData)
        """
        return message
    }

    // MARK: - Bundle Truncation

    private static func truncateBundle(
        _ bundle: HealthDataBundle,
        targetCharacters: Int
    ) -> HealthDataBundle {
        let categoryCount = max(1, bundle.categories.count)
        let budgetPerCategory = max(500, targetCharacters / categoryCount)
        var truncated: [String: [SerializedHealthRecord]] = [:]

        for (key, records) in bundle.categories {
            // Group by typeIdentifier so every metric type gets representation.
            var byType: [String: [SerializedHealthRecord]] = [:]
            for record in records {
                byType[record.typeIdentifier, default: []].append(record)
            }
            let typeCount = max(1, byType.count)
            // Nutrition has 34 types — give each type at least 7 records (one per day in a week)
            // so weekly analysis covers all nutrients. Other categories get a minimum of 2.
            let minRecs = key == HealthCategory.nutrition.rawValue ? 7 : 2
            let recsPerType = max(minRecs, budgetPerCategory / (typeCount * 150))
            var result: [SerializedHealthRecord] = []
            for typeRecords in byType.values {
                result.append(contentsOf: typeRecords.suffix(recsPerType))
            }
            result.sort { $0.date < $1.date }
            truncated[key] = result
        }

        return HealthDataBundle(
            dateRangeStart: bundle.dateRangeStart,
            dateRangeEnd: bundle.dateRangeEnd,
            categories: truncated,
            metadata: bundle.metadata
        )
    }

    // MARK: - Date Range Inference from Query

    /// Infers how many days of health data to fetch from the user's natural-language query.
    /// Examples: "last 7 days" → 7, "this week" → 7, "past 3 months" → 90.
    /// Returns 7 (one week) when no time reference is found — enough for most health questions
    /// without over-fetching and inflating the prompt size.
    static func inferDateRangeDays(from query: String) -> Int {
        // Normalise word-numbers before numeric pattern matching.
        let normalised = normaliseTimeWords(query.lowercased())

        // Numeric patterns first (most specific): "X days", "X weeks", "X months", "X years".
        if let n = extractInteger(preceding: "day",   in: normalised), n > 0 { return clampDays(n) }
        if let n = extractInteger(preceding: "week",  in: normalised), n > 0 { return clampDays(n * 7) }
        if let n = extractInteger(preceding: "month", in: normalised), n > 0 { return clampDays(n * 30) }
        if let n = extractInteger(preceding: "year",  in: normalised), n > 0 { return clampDays(n * 365) }

        // Named periods (no number). Check shortest periods first to avoid false matches.
        if normalised.contains("today") || normalised.contains("right now") { return 1 }
        if normalised.contains("yesterday")                                  { return 2 }
        // \bweek\b won't match "weeks" (already handled above); safe to use here.
        if normalised.range(of: #"\bweek\b"#,    options: .regularExpression) != nil { return 7   }
        if normalised.range(of: #"\bmonth\b"#,   options: .regularExpression) != nil { return 30  }
        if normalised.range(of: #"\bquarter\b"#, options: .regularExpression) != nil { return 90  }
        if normalised.range(of: #"\byear\b"#,    options: .regularExpression) != nil { return 365 }
        if normalised.contains("recent")                                     { return 14 }
        if normalised.contains("few days")                                   { return 7  }

        return 7 // default — a week of data is the right balance for unfocused queries
    }

    private static func normaliseTimeWords(_ text: String) -> String {
        // "a week" / "a month" → "1 week" / "1 month" so the numeric path picks them up.
        let wordMap: [(String, String)] = [
            ("a week", "1 week"), ("a month", "1 month"), ("a year", "1 year"),
            ("one", "1"), ("two", "2"), ("three", "3"), ("four", "4"), ("five", "5"),
            ("six", "6"), ("seven", "7"), ("eight", "8"), ("nine", "9"), ("ten", "10"),
            ("eleven", "11"), ("twelve", "12"), ("fourteen", "14"), ("fifteen", "15"),
            ("twenty", "20"), ("thirty", "30"), ("sixty", "60"), ("ninety", "90"),
        ]
        var result = text
        for (word, digit) in wordMap {
            result = result.replacingOccurrences(of: word, with: digit)
        }
        return result
    }

    /// Extracts the integer immediately before `unit` in `text`.
    /// Matches "7 days", "7-day", "past 7 days", "7days", etc.
    private static func extractInteger(preceding unit: String, in text: String) -> Int? {
        let pattern = #"(\d+)\s*[-–]?\s*"# + unit
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let digits = String(text[range])
            .unicodeScalars
            .filter { CharacterSet.decimalDigits.contains($0) }
            .map { String($0) }
            .joined()
        return Int(digits)
    }

    private static func clampDays(_ value: Int) -> Int {
        Swift.max(1, Swift.min(730, value))
    }

    // MARK: - Category Detection from Query

    /// Infers which health categories are relevant from a natural language query.
    static func detectCategories(from query: String) -> [HealthCategory] {
        let lower = query.lowercased()
        var detected: Set<HealthCategory> = []

        let keywords: [HealthCategory: [String]] = [
            .activity:     ["step", "walk", "run", "exercise", "workout", "calories", "distance", "cycling", "active"],
            .body:         ["weight", "bmi", "height", "fat", "lean", "waist", "body", "composition"],
            .heart:        ["heart", "resting", "pulse", "hrv", "vo2", "ecg", "cardiac", "bpm", "arrhythmia", "afib", "rhythm", "cardio"],
            .sleep:        ["sleep", "rem", "deep sleep", "insomnia", "rest", "tired", "fatigue", "nap"],
            .nutrition:    ["eat", "food", "calorie", "protein", "carb", "fat", "diet", "nutrition", "water", "caffeine", "vitamin", "mineral"],
            .vitals:       ["blood pressure", "oxygen", "spo2", "respiratory", "temperature", "bp", "breathing", "spirometry", "lung"],
            .mindfulness:  ["meditation", "mindful", "stress", "mental", "anxiety", "calm", "toothbrush", "handwash"],
            .reproductive: ["menstrual", "cycle", "ovulation", "reproductive", "period", "pregnancy"],
            .labs:         ["glucose", "sugar", "blood test", "cholesterol", "lab", "insulin"],
            .environment:  ["noise", "audio", "uv", "ultraviolet", "environmental", "sound", "decibel"],
        ]

        for (category, words) in keywords {
            if words.contains(where: { lower.contains($0) }) {
                detected.insert(category)
            }
        }

        // Default to activity + heart if nothing specific detected
        if detected.isEmpty {
            detected = [.activity, .heart, .sleep]
        }

        return Array(detected).sorted { $0.rawValue < $1.rawValue }
    }
}

import SwiftUI
import SwiftData
import OSLog

// MARK: - Expertise Level

enum HealthExpertiseLevel: String, CaseIterable {
    case novice       = "novice"
    case intermediate = "intermediate"
    case expert       = "expert"

    var displayName: String {
        switch self {
        case .novice:       return "Novice"
        case .intermediate: return "Intermediate"
        case .expert:       return "Expert"
        }
    }
    var systemImage: String {
        switch self {
        case .novice:       return "graduationcap"
        case .intermediate: return "chart.bar.fill"
        case .expert:       return "brain.head.profile"
        }
    }
}

// MARK: - QueryViewModel
@MainActor
@Observable
final class QueryViewModel {
    var queryText: String = ""
    /// All sessions in the current in-progress conversation (oldest first).
    var conversationSessions: [AnalysisSession] = []
    /// The session currently streaming or most recently completed.
    var currentSession: AnalysisSession? { conversationSessions.last }
    var liveRecords: [SerializedHealthRecord] = []
    var isLoading: Bool = false
    var error: String?
    var showProviderPicker: Bool = false
    /// Date range used for the current fetch — inferred from the query, never user-facing.
    private var dateRangeDays: Int = 7

    /// Expertise level — persisted to UserDefaults so it survives app restarts.
    var expertiseLevel: HealthExpertiseLevel = HealthExpertiseLevel(
        rawValue: UserDefaults.standard.string(forKey: "healthExpertiseLevel") ?? "intermediate"
    ) ?? .intermediate {
        didSet { UserDefaults.standard.set(expertiseLevel.rawValue, forKey: "healthExpertiseLevel") }
    }

    let aiRouter: AIServiceRouter
    private let fetcher: HealthDataFetcher
    private let healthKitService: HealthKitService
    private var modelContext: ModelContext?
    private var streamTask: Task<Void, Never>?

    /// Previous Q&A pairs in this conversation — sent as context for follow-ups.
    private var conversationHistory: [(query: String, response: String)] = []
    /// Cached health data bundle reused for follow-up queries to avoid redundant fetches.
    private var cachedBundle: HealthDataBundle?
    /// When the bundle was cached — used to detect stale data (different day or >4 hours old).
    private var cachedBundleDate: Date?
    private var cachedCategories: [HealthCategory] = []

    var suggestedQueries: [String] {
        QuerySuggestions.general
    }

    var activeProvider: AIProviderType { aiRouter.activeProviderType }
    var activeModelID: String { aiRouter.activeModelID }
    var availableModels: [AIModelDescriptor] { aiRouter.availableModels }
    var hasActiveConversation: Bool { !conversationSessions.isEmpty }

    init(aiRouter: AIServiceRouter, fetcher: HealthDataFetcher) {
        self.aiRouter = aiRouter
        self.fetcher = fetcher
        self.healthKitService = HealthKitService.shared
    }

    func setContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - New Conversation

    func startNewConversation() {
        streamTask?.cancel()
        streamTask = nil
        currentSession?.isStreaming = false
        conversationSessions = []
        conversationHistory = []
        cachedBundle = nil
        cachedBundleDate = nil
        cachedCategories = []
        liveRecords = []
        isLoading = false
        error = nil
        queryText = ""
    }

    // MARK: - Submit Query

    func submitQuery() async {
        let query = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        queryText = ""          // clear immediately — field is ready for next input
        guard !query.isEmpty, !isLoading, let context = modelContext else { return }
        streamTask?.cancel()
        isLoading = true
        error = nil

        // A follow-up reuses the cached bundle IF it's from the same calendar day
        // AND less than 4 hours old — otherwise re-fetch so latest health data is used.
        // We only count it as a follow-up if conversationHistory is non-empty, meaning
        // at least one prior turn succeeded. This prevents a failed attempt (e.g. an
        // on-device "Exceeded model context window" response) from poisoning the cache
        // so the next query (possibly with a different provider) incorrectly skips the
        // full data payload.
        let isCacheStale: Bool = {
            guard let bundleDate = cachedBundleDate else { return true }
            let tooOld = Date().timeIntervalSince(bundleDate) > 4 * 3600
            let differentDay = !Calendar.current.isDate(bundleDate, inSameDayAs: Date())
            return tooOld || differentDay
        }()
        let isFollowUp = cachedBundle != nil && !conversationHistory.isEmpty && !isCacheStale

        if isFollowUp {
            // Continue the conversation with cached data and history.
            return await performQuery(
                query: query,
                categories: cachedCategories,
                context: context,
                isFollowUp: true
            )
        }

        // Fresh query — infer date range from the query text.
        // "last 7 days" → 7, "this month" → 30, no mention → 7 (silent default).
        dateRangeDays = PromptBuilder.inferDateRangeDays(from: query)

        // Always (re-)request HealthKit authorization before fetching.
        // HealthKit is idempotent: calling requestAuthorization for already-authorized
        // types silently succeeds without showing a dialog. This ensures we recover
        // from cases where a previous authorization attempt failed (e.g. missing
        // entitlement) but the categories were already marked as granted in prefs.
        let allNonSensitive = HealthKitPermissions.categories(upToTier: 0)

        let isOnDevice = aiRouter.activeModelDescriptor?.isOnDevice ?? false
        if healthKitService.isAvailable {
            let prefs = UserPreferences.fetch(in: context)
            try? await healthKitService.requestAuthorization(for: allNonSensitive)
            for category in allNonSensitive { prefs.markCategoryGranted(category) }
            let sensitiveOptedIn = HealthKitPermissions.sensitiveGroup.categories
                .filter { prefs.isHealthCategoryGranted($0) }
            try? context.save()
            let allCategories = allNonSensitive + sensitiveOptedIn
            // For specific questions (e.g. "how is my sleep?") limit the fetch to
            // the relevant category and its closely related peers to keep the prompt
            // focused and under the context budget. For broad / general health queries
            // fetch everything so the AI can reason holistically across all metrics.
            // On-device models skip related categories entirely to stay within their
            // tight context window.
            let fetchCategories = smartCategories(for: query, permitted: allCategories, onDevice: isOnDevice)
            return await performQuery(query: query, categories: fetchCategories, context: context, isFollowUp: false)
        } else {
            let fetchCategories = smartCategories(for: query, permitted: allNonSensitive, onDevice: isOnDevice)
            return await performQuery(query: query, categories: fetchCategories, context: context, isFollowUp: false)
        }
    }

    /// Returns an appropriate subset of permitted categories for a query.
    /// General / broad health queries get all categories; specific single-topic
    /// queries get the detected category plus its directly related peers.
    /// On-device models skip related peers to keep the prompt within their tight context window.
    private func smartCategories(for query: String, permitted: [HealthCategory], onDevice: Bool = false) -> [HealthCategory] {
        let detected = PromptBuilder.detectCategories(from: query)
        // If ≥3 distinct categories detected (or the fallback default set was returned),
        // treat this as a general health question and send everything.
        // On-device: still restrict to detected only to avoid context overflow.
        guard detected.count < 3 else {
            if onDevice {
                let permittedSet = Set(permitted)
                let result = detected.filter { permittedSet.contains($0) }
                return result.isEmpty ? Array(permittedSet.prefix(3)) : result
            }
            return permitted
        }

        if onDevice {
            // On-device models have a tight context window — send ONLY the directly
            // detected categories. Skipping related peers cuts the data payload by
            // 60–80 %, easily fitting within the 4 096-token on-device context.
            let permittedSet = Set(permitted)
            let result = detected.filter { permittedSet.contains($0) }
            return result.isEmpty ? Array(permittedSet.prefix(2)) : result
        }

        // Related categories for holistic context around a specific topic.
        // Vitals (blood oxygen, respiratory rate, etc.) are always included as related
        // so the AI always has this data and never falsely reports it as missing.
        let related: [HealthCategory: [HealthCategory]] = [
            .activity:     [.heart, .sleep, .body, .nutrition, .vitals],
            .sleep:        [.heart, .activity, .mindfulness, .vitals],
            .heart:        [.activity, .sleep, .body, .vitals],
            .nutrition:    [.body, .activity, .vitals],
            .body:         [.heart, .activity, .nutrition, .vitals],
            .vitals:       [.heart, .body, .labs],
            .mindfulness:  [.heart, .sleep, .vitals],
            .labs:         [.body, .nutrition, .vitals],
            .environment:  [.vitals, .heart],
            .reproductive: [.body, .vitals],
        ]
        var cats = Set(detected)
        for cat in detected { cats.formUnion(related[cat] ?? []) }
        let permittedSet = Set(permitted)
        return Array(cats.intersection(permittedSet)).sorted { $0.rawValue < $1.rawValue }
    }

    private func performQuery(
        query: String,
        categories: [HealthCategory],
        context: ModelContext,
        isFollowUp: Bool
    ) async {
        let session = AnalysisSession(
            queryText: query,
            providerRawValue: aiRouter.activeProviderType.rawValue,
            providerModel: aiRouter.activeModelID,
            categories: categories
        )
        session.isStreaming = true
        context.insert(session)
        conversationSessions.append(session)

        // end = right now, so all data up to the current moment is included.
        // (Previously capped at midnight + 14 h, which excluded afternoon data.)
        let end = Date()
        // Start at midnight of (today − dateRangeDays) to get full calendar days.
        // Then subtract one extra day so sleep starting the evening before the window
        // (e.g., 11 PM) is always captured even at the boundary.
        let windowStart = Calendar.current.date(byAdding: .day, value: -dateRangeDays, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        let start = Calendar.current.date(byAdding: .day, value: -1, to: windowStart) ?? windowStart
        let range = DateInterval(start: start, end: end)
        let maxChars = aiRouter.activeModelDescriptor?.maxPromptCharacters ?? 80_000
        let isOnDevice = aiRouter.activeModelDescriptor?.isOnDevice ?? false
        let history = conversationHistory   // capture snapshot before async gap

        // Fetch weather context in parallel with HealthKit fetch (non-blocking).
        // Location coordinates are never sent to AI — only city name, country, season, weather text.
        async let weatherFetch = WeatherContextService.shared.fetchContext()

        do {
            let userMessage: String
            let systemPrompt: String

            if isFollowUp, let cached = cachedBundle {
                // ── Follow-up path ──────────────────────────────────────────
                let level = expertiseLevel   // capture before Task.detached
                let onDevice = isOnDevice     // capture before Task.detached
                let weather = await weatherFetch   // await weather result
                (userMessage, systemPrompt) = try await Task.detached(priority: .userInitiated) {
                    let msg = try PromptBuilder.buildMessage(
                        query: query,
                        bundle: cached,
                        maxCharacters: maxChars,
                        level: level,
                        weatherContext: weather,
                        conversationHistory: history
                    )
                    let sys = PromptBuilder.systemPrompt(level: level, isOnDevice: onDevice)
                    Logger.ai.info("Follow-up prompt built: \(msg.count) chars (cached bundle)")
                    return (msg, sys)
                }.value
                // liveRecords stays as-is from initial fetch — charts keep working.

            } else {
                // ── First query path ─────────────────────────────────────────
                liveRecords = []
                let bundle = try await fetcher.fetch(for: categories, dateRange: range, granularity: .daily)
                let recordCount = bundle.metadata.totalRecordCount

                let dayRange = dateRangeDays
                Logger.healthKit.info("HealthKit fetch complete: \(recordCount) records across \(bundle.categories.count) categories for \(dayRange)-day window")

                // Hard stop if HealthKit returned nothing — don't waste an API call
                // with an empty prompt. Guide the user to fix their permissions instead.
                if recordCount == 0 {
                    session.responseText = """
                    ⚠️ **No health data was retrieved for the last \(dayRange) days.**

                    This usually means HealthKit permissions haven't been fully granted yet. To fix it:

                    1. Open the **Health** app on your iPhone
                    2. Tap your profile photo → **Apps** → **HealthLens**
                    3. Enable all categories you want analysed
                    4. Return here and try your question again

                    If you've already granted permissions, try going to **Settings → Privacy & Security → Health → HealthLens** and toggling the categories on.
                    """
                    session.isStreaming = false
                    self.error = "No health data found. Check Health permissions and try again."
                    try? context.save()
                    isLoading = false
                    return
                }

                let level = expertiseLevel   // capture before Task.detached
                let onDevice = isOnDevice     // capture before Task.detached
                let weather = await weatherFetch   // await weather result
                let (msg, sys, records, payloadJSON) = try await Task.detached(priority: .userInitiated) {
                    let m = try PromptBuilder.buildMessage(
                        query: query,
                        bundle: bundle,
                        maxCharacters: maxChars,
                        level: level,
                        weatherContext: weather,
                        conversationHistory: history
                    )
                    let s = PromptBuilder.systemPrompt(level: level, isOnDevice: onDevice)
                    let recs: [SerializedHealthRecord] = bundle.categories.values.flatMap { $0 }
                    let json = (try? JSONEncoder().encode(bundle)) ?? Data()
                    Logger.ai.info("Prompt built: \(m.count) chars total for \(recs.count) health records")
                    return (m, s, recs, json)
                }.value

                // Cache for subsequent follow-ups (stamped with current time for staleness check).
                liveRecords = records
                cachedBundle = bundle
                cachedBundleDate = Date()
                cachedCategories = categories

                // Persist snapshot so charts work even after a restart.
                let serializer = HealthDataSerializer()
                let snapshot = HealthSnapshot(start: start, end: end, payloadJSON: payloadJSON)
                for record in records { snapshot.dataPoints.append(serializer.makeDataPoint(from: record)) }
                session.snapshot = snapshot
                context.insert(snapshot)

                userMessage = msg
                systemPrompt = sys
            }

            let request = AIRequest(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                modelID: aiRouter.activeModelID,
                maxTokens: Constants.AI.defaultMaxTokens,
                temperature: Constants.AI.defaultTemperature,
                stream: true
            )

            let startTime = Date()
            var accumulatedText = ""

            streamTask = Task { @MainActor in
                do {
                    var lastUIUpdate = Date.distantPast
                    for try await chunk in aiRouter.stream(request) {
                        accumulatedText += chunk
                        let now = Date()
                        if now.timeIntervalSince(lastUIUpdate) >= 0.033 {
                            session.responseText = accumulatedText
                            lastUIUpdate = now
                        }
                    }
                    session.responseText = accumulatedText.isEmpty ? "No response received." : accumulatedText
                } catch is CancellationError {
                    if !accumulatedText.isEmpty { session.responseText = accumulatedText }
                } catch {
                    session.responseText = accumulatedText.isEmpty
                        ? "⚠️ \(error.localizedDescription)"
                        : accumulatedText
                }

                session.isStreaming = false
                session.latencyMS = Date().timeIntervalSince(startTime) * 1000
                session.updatedAt = Date()

                // Record exchange in conversation history for subsequent follow-ups.
                // Exclude: app-level errors (⚠️ prefix), and model-level failures such as
                // "Exceeded model context window size" which indicate the data never reached
                // the model. Including these would mark the conversation as having a valid
                // prior exchange and incorrectly trigger the follow-up path on the next query.
                let looksLikeError = session.responseText.hasPrefix("⚠️")
                    || session.responseText.lowercased().contains("exceeded")
                    || session.responseText.lowercased().contains("context window")
                    || session.responseText.isEmpty
                if !looksLikeError {
                    conversationHistory.append((query: session.queryText, response: session.responseText))
                }

                do {
                    try context.save()
                    if !session.responseText.hasPrefix("⚠️") { triggerHaptic(.success) }
                } catch {
                    Logger.persistence.error("Failed to save session: \(error)")
                }
                isLoading = false
            }

        } catch let aiError as AIError {
            session.responseText = "⚠️ \(aiError.localizedDescription)"
            session.isStreaming = false
            try? context.save()
            self.error = aiError.localizedDescription
            isLoading = false
        } catch {
            session.responseText = "⚠️ Failed to fetch health data: \(error.localizedDescription)"
            session.isStreaming = false
            try? context.save()
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    // MARK: - Provider / Model switching

    func setProvider(_ type: AIProviderType, modelID: String) {
        aiRouter.setProvider(type, modelID: modelID)
    }

    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        currentSession?.isStreaming = false
        isLoading = false
    }

    /// Restores a previously saved session so the user can read it and ask follow-ups.
    /// The saved session's Q&A is injected into conversation history; a fresh health fetch
    /// will occur on the next query since we don't have a cached bundle for past sessions.
    func loadExistingSession(_ session: AnalysisSession) {
        streamTask?.cancel()
        streamTask = nil
        isLoading = false
        error = nil
        queryText = ""
        conversationSessions = [session]
        conversationHistory = [(query: session.queryText, response: session.responseText)]
        cachedBundle = nil
        cachedBundleDate = nil
        cachedCategories = session.categories
    }
}


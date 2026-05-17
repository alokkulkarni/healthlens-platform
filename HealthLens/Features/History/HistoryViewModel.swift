import SwiftUI

@MainActor
@Observable
final class HistoryViewModel {
    var searchText: String = ""
    var selectedCategories: Set<HealthCategory> = []
    var showFavoritesOnly: Bool = false
    var selectedProvider: AIProviderType? = nil

    enum DateBucket: String, CaseIterable {
        case today = "Today"
        case thisWeek = "This Week"
        case thisMonth = "This Month"
        case older = "Older"

        func contains(_ date: Date) -> Bool {
            let cal = Calendar.current
            let now = Date()
            switch self {
            case .today:     return cal.isDateInToday(date)
            case .thisWeek:  return !cal.isDateInToday(date) && cal.isDate(date, equalTo: now, toGranularity: .weekOfYear)
            case .thisMonth: return !cal.isDate(date, equalTo: now, toGranularity: .weekOfYear) && cal.isDate(date, equalTo: now, toGranularity: .month)
            case .older:     return !cal.isDate(date, equalTo: now, toGranularity: .month)
            }
        }
    }

    func filtered(_ sessions: [AnalysisSession]) -> [AnalysisSession] {
        sessions.filter { session in
            // Search text
            if !searchText.isEmpty {
                let text = searchText.lowercased()
                let matchQuery = session.queryText.lowercased().contains(text)
                let matchResponse = session.responseText.lowercased().contains(text)
                if !matchQuery && !matchResponse { return false }
            }

            // Category filter
            if !selectedCategories.isEmpty {
                let sessionCategories = Set(session.categories)
                if sessionCategories.isDisjoint(with: selectedCategories) { return false }
            }

            // Favorites filter
            if showFavoritesOnly && !session.isFavorited { return false }

            // Provider filter
            if let provider = selectedProvider, session.provider != provider { return false }

            return true
        }
    }

    func grouped(_ sessions: [AnalysisSession]) -> [(DateBucket, [AnalysisSession])] {
        DateBucket.allCases.compactMap { bucket in
            let bucketSessions = sessions.filter { bucket.contains($0.createdAt) }
            return bucketSessions.isEmpty ? nil : (bucket, bucketSessions)
        }
    }
}

import SwiftUI
import SwiftData

@MainActor
@Observable
final class SettingsViewModel {
    var showDeleteConfirmation = false
    var totalSessionCount: Int = 0
    var totalDataSize: String = "Calculating…"
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    func loadStats(sessions: [AnalysisSession]) {
        totalSessionCount = sessions.count
        let estimatedBytes = sessions.reduce(0) { $0 + $1.responseText.count + $1.queryText.count }
        totalDataSize = ByteCountFormatter.string(fromByteCount: Int64(estimatedBytes), countStyle: .file)
    }
}

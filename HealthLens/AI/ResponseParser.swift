import Foundation

/// Parses AI response text into a structured display model.
struct ParsedAIResponse {
    var fullText: String
    var sections: [ResponseSection]
    var suggestedCharts: [ChartSuggestion]
    var suggestedFollowUps: [String]
    var hasClinicalWarning: Bool
}

struct ResponseSection: Identifiable {
    var id = UUID()
    var heading: String?
    var body: String
    var isWarning: Bool
}

struct ChartSuggestion: Identifiable, Codable {
    var id = UUID()
    var category: String          // HealthCategory.rawValue
    var chartType: String         // "line" | "bar" | "scatter" | "heatmap" | "range"
    var typeIdentifier: String    // HKQuantityTypeIdentifier rawValue
    var title: String
    var description: String
}

struct ResponseParser {
    func parse(_ text: String) -> ParsedAIResponse {
        let sections = extractSections(from: text)
        let charts = extractChartSuggestions(from: text)
        let followUps = extractFollowUps(from: text)
        let hasClinicalWarning = text.lowercased().contains("consult") ||
                                  text.lowercased().contains("doctor") ||
                                  text.lowercased().contains("medical") ||
                                  text.lowercased().contains("physician")

        return ParsedAIResponse(
            fullText: text,
            sections: sections,
            suggestedCharts: charts,
            suggestedFollowUps: followUps,
            hasClinicalWarning: hasClinicalWarning
        )
    }

    // MARK: - Sections

    private func extractSections(from text: String) -> [ResponseSection] {
        var sections: [ResponseSection] = []
        let lines = text.components(separatedBy: .newlines)
        var currentHeading: String?
        var currentBody = ""

        for line in lines {
            if line.hasPrefix("## ") || line.hasPrefix("# ") {
                if !currentBody.trimmingCharacters(in: .whitespaces).isEmpty {
                    sections.append(ResponseSection(
                        heading: currentHeading,
                        body: currentBody.trimmingCharacters(in: .whitespacesAndNewlines),
                        isWarning: currentBody.lowercased().contains("consult") || currentBody.lowercased().contains("warning")
                    ))
                }
                currentHeading = line.replacingOccurrences(of: "## ", with: "")
                    .replacingOccurrences(of: "# ", with: "")
                currentBody = ""
            } else {
                currentBody += line + "\n"
            }
        }

        if !currentBody.trimmingCharacters(in: .whitespaces).isEmpty {
            sections.append(ResponseSection(
                heading: currentHeading,
                body: currentBody.trimmingCharacters(in: .whitespacesAndNewlines),
                isWarning: false
            ))
        }

        return sections.isEmpty ? [ResponseSection(heading: nil, body: text, isWarning: false)] : sections
    }

    // MARK: - Chart Suggestions

    private func extractChartSuggestions(from text: String) -> [ChartSuggestion] {
        // Look for chart suggestion section
        guard let chartSection = extractSection(from: text, heading: "Chart Suggestions") else {
            return defaultCharts(for: text)
        }

        var charts: [ChartSuggestion] = []
        let lines = chartSection.components(separatedBy: .newlines)
        for line in lines {
            let lower = line.lowercased()
            if lower.contains("heart rate") || lower.contains("bpm") {
                charts.append(ChartSuggestion(
                    category: "heart",
                    chartType: "line",
                    typeIdentifier: "HKQuantityTypeIdentifierHeartRate",
                    title: "Heart Rate Trend",
                    description: "Heart rate over time"
                ))
            } else if lower.contains("step") {
                charts.append(ChartSuggestion(
                    category: "activity",
                    chartType: "bar",
                    typeIdentifier: "HKQuantityTypeIdentifierStepCount",
                    title: "Daily Steps",
                    description: "Steps per day"
                ))
            } else if lower.contains("sleep") {
                charts.append(ChartSuggestion(
                    category: "sleep",
                    chartType: "bar",
                    typeIdentifier: "HKCategoryTypeIdentifierSleepAnalysis",
                    title: "Sleep Duration",
                    description: "Sleep hours per night"
                ))
            } else if lower.contains("weight") {
                charts.append(ChartSuggestion(
                    category: "body",
                    chartType: "line",
                    typeIdentifier: "HKQuantityTypeIdentifierBodyMass",
                    title: "Weight Trend",
                    description: "Body weight over time"
                ))
            } else if lower.contains("blood pressure") || lower.contains("bp") {
                charts.append(ChartSuggestion(
                    category: "vitals",
                    chartType: "range",
                    typeIdentifier: "HKQuantityTypeIdentifierBloodPressureSystolic",
                    title: "Blood Pressure",
                    description: "Systolic / Diastolic range"
                ))
            }
        }
        return charts.isEmpty ? defaultCharts(for: text) : Array(charts.prefix(3))
    }

    private func defaultCharts(for text: String) -> [ChartSuggestion] {
        var charts: [ChartSuggestion] = []
        let lower = text.lowercased()
        if lower.contains("heart") || lower.contains("cardio") {
            charts.append(ChartSuggestion(
                category: "heart",
                chartType: "line",
                typeIdentifier: "HKQuantityTypeIdentifierHeartRate",
                title: "Heart Rate",
                description: "Heart rate trend"
            ))
        }
        if lower.contains("step") || lower.contains("walk") || lower.contains("activity") {
            charts.append(ChartSuggestion(
                category: "activity",
                chartType: "bar",
                typeIdentifier: "HKQuantityTypeIdentifierStepCount",
                title: "Daily Steps",
                description: "Steps per day"
            ))
        }
        if lower.contains("sleep") {
            charts.append(ChartSuggestion(
                category: "sleep",
                chartType: "heatmap",
                typeIdentifier: "HKCategoryTypeIdentifierSleepAnalysis",
                title: "Sleep Pattern",
                description: "Weekly sleep heatmap"
            ))
        }
        return charts
    }

    // MARK: - Follow-ups

    private func extractFollowUps(from text: String) -> [String] {
        // Scan for bullet points or numbered items after "follow-up" heading
        guard let section = extractSection(from: text, heading: "Follow-up") ??
              extractSection(from: text, heading: "Suggested Questions") else {
            return generateDefaultFollowUps(from: text)
        }

        return section.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("-") || $0.first?.isNumber == true }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-0123456789. ")) }
            .filter { !$0.isEmpty }
            .prefix(4)
            .map { String($0) }
    }

    private func generateDefaultFollowUps(from text: String) -> [String] {
        var followUps: [String] = []
        let lower = text.lowercased()
        if lower.contains("sleep") { followUps.append("How has my sleep quality changed over the last 3 months?") }
        if lower.contains("heart") { followUps.append("What's my resting heart rate trend this year?") }
        if lower.contains("step") { followUps.append("How do my step counts compare between weekdays and weekends?") }
        if lower.contains("weight") { followUps.append("Is there a correlation between my exercise and weight?") }
        return Array(followUps.prefix(3))
    }

    // MARK: - Helper

    private func extractSection(from text: String, heading: String) -> String? {
        let pattern = "## ?\(heading)"
        guard let range = text.range(of: pattern, options: .regularExpression),
              !range.isEmpty else { return nil }
        let start = range.upperBound
        let remainder = String(text[start...])
        if let nextHeading = remainder.range(of: "##", options: .literal) {
            return String(remainder[..<nextHeading.lowerBound])
        }
        return remainder
    }
}

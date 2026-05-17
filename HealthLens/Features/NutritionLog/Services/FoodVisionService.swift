import Foundation
import UIKit
import OSLog

private let logger = Logger(subsystem: "com.healthlens", category: "FoodVisionService")

// MARK: - Food Vision Service

final class FoodVisionService: Sendable {
    static let shared = FoodVisionService()
    private init() {}

    // Strict schema prompt — forces JSON-only output with full 23-field nutrition palette.
    private let systemPrompt = """
You are a nutrition database. Output ONLY a valid JSON object — no markdown, no fences, no explanation, no preamble. Start your response with { and end with }.
Use this exact template, replacing 0 with estimated numeric values:
{"foodName":"string","servingSize":"string","confidence":"high|medium|low","nutrition":{"calories":0,"protein":0,"carbohydrates":0,"fat":0,"saturatedFat":0,"monounsaturatedFat":0,"polyunsaturatedFat":0,"fiber":0,"sugar":0,"sodium":0,"cholesterol":0,"potassium":0,"calcium":0,"iron":0,"zinc":0,"magnesium":0,"vitaminA":0,"vitaminC":0,"vitaminD":0,"vitaminB6":0,"vitaminB12":0,"folate":0,"water":0}}
Rules: foodName is a short dish name (max 60 chars). servingSize is a SHORT string like "350g" or "1 bowl" — no descriptions, max 20 chars. All nutrition values must be plain numbers. Units: calories=kcal; protein/carbohydrates/fat/saturatedFat/monounsaturatedFat/polyunsaturatedFat/fiber/sugar=grams; sodium/cholesterol/potassium/calcium/iron/zinc/magnesium/vitaminC/vitaminB6=mg; vitaminA/vitaminD/vitaminB12/folate=mcg; water=mL. Use 0 for unknown. Output ONLY the JSON object, nothing else.
"""

    // MARK: - Public API

    /// Analyse a food image using the specified provider.
    /// On-device and Bedrock do not support vision — pass .gemini or .claude for image analysis.
    func analyzeFood(
        image: UIImage,
        userContext: String = "",
        provider: AIProviderType = .gemini,
        modelID: String = "gemini-2.5-flash"
    ) async throws -> ScannedMeal {
        guard let compressed = compressImage(image) else {
            throw FoodVisionError.imageCompressionFailed
        }
        let base64 = compressed.base64EncodedString()
        let responseText: String
        switch provider {
        case .gemini:
            responseText = try await callGemini(imageBase64: base64, userContext: userContext, modelID: modelID)
        case .claude:
            responseText = try await callClaude(imageBase64: base64, userContext: userContext, modelID: modelID)
        case .onDevice, .bedrock:
            throw FoodVisionError.visionNotSupported("Image analysis requires Gemini or Claude. Please switch provider in settings.")
        }
        return try parseResponse(responseText, imageData: compressed)
    }

    /// Analyse a meal described in text — no photo required. Supports all providers including on-device.
    func describeFood(
        text: String,
        provider: AIProviderType = .gemini,
        modelID: String = "gemini-2.5-flash"
    ) async throws -> ScannedMeal {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FoodVisionError.emptyDescription
        }
        let responseText: String
        switch provider {
        case .gemini:
            responseText = try await callGeminiText(description: text, modelID: modelID)
        case .claude:
            responseText = try await callClaudeText(description: text, modelID: modelID)
        case .onDevice:
            responseText = try await callOnDeviceText(description: text)
        case .bedrock:
            responseText = try await callBedrockText(description: text, modelID: modelID)
        }
        return try parseResponse(responseText, imageData: nil)
    }

    // MARK: - Image Compression

    private func compressImage(_ image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1280
        let size = image.size
        var targetSize = size
        if size.width > maxDimension || size.height > maxDimension {
            let scale = maxDimension / max(size.width, size.height)
            targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        }
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }

    // MARK: - Gemini Vision Call

    private func callGemini(imageBase64: String, userContext: String, modelID: String = "gemini-2.5-flash") async throws -> String {
        let keyStore = APIKeyStore()
        let apiKey: String
        do { apiKey = try keyStore.retrieveGeminiKey() }
        catch { throw FoodVisionError.missingAPIKey("Gemini") }

        let urlString = "\(Constants.API.geminiBaseURL)/\(modelID):generateContent"
        guard let url = URL(string: urlString) else {
            throw FoodVisionError.invalidURL
        }

        let userText = userContext.isEmpty
            ? "Analyze this food image and return JSON only, no explanation."
            : "Analyze this food image. Context: \(userContext). Return JSON only, no explanation."

        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": [[
                "role": "user",
                "parts": [
                    ["inline_data": ["mime_type": "image/jpeg", "data": imageBase64]],
                    ["text": userText]
                ]
            ]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "maxOutputTokens": 4096,
                "temperature": 1.0,
                "thinkingConfig": ["thinkingBudget": 0]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FoodVisionError.networkError("No HTTP response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw FoodVisionError.apiError(httpResponse.statusCode, body)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else {
            throw FoodVisionError.malformedResponse("Could not extract text from Gemini response")
        }
        // Concatenate ALL parts — Gemini can split JSON across multiple parts
        let text = parts.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else {
            throw FoodVisionError.malformedResponse("Empty response from Gemini")
        }
        return text
    }

    private func callClaude(imageBase64: String, userContext: String, modelID: String = "claude-haiku-4-5-20251001") async throws -> String {
        let keyStore = APIKeyStore()
        let apiKey: String
        do { apiKey = try keyStore.retrieveClaudeKey() }
        catch { throw FoodVisionError.missingAPIKey("Claude") }

        guard let url = URL(string: Constants.API.claudeBaseURL) else {
            throw FoodVisionError.invalidURL
        }

        let userText = userContext.isEmpty
            ? "Analyze this food image and return JSON only, no explanation."
            : "Analyze this food image. Context: \(userContext). Return JSON only, no explanation."

        let body: [String: Any] = [
            "model": modelID,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": imageBase64
                            ]
                        ],
                        ["type": "text", "text": userText]
                    ]
                ],
                ["role": "assistant", "content": "{"]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Constants.API.claudeAPIVersion, forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FoodVisionError.networkError("No HTTP response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? "unknown"
            throw FoodVisionError.apiError(httpResponse.statusCode, bodyStr)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String
        else {
            throw FoodVisionError.malformedResponse("Could not extract text from Claude response")
        }
        return "{" + text
    }

    private func callGeminiText(description: String, modelID: String = "gemini-2.5-flash") async throws -> String {
        let keyStore = APIKeyStore()
        let apiKey: String
        do { apiKey = try keyStore.retrieveGeminiKey() }
        catch { throw FoodVisionError.missingAPIKey("Gemini") }

        let urlString = "\(Constants.API.geminiBaseURL)/\(modelID):generateContent"
        guard let url = URL(string: urlString) else { throw FoodVisionError.invalidURL }

        let userText = "Estimate the nutrition for this meal: \(description). Return JSON only, no explanation."

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": systemPrompt]]],
            "contents": [[
                "role": "user",
                "parts": [["text": userText]]
            ]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "maxOutputTokens": 4096,
                "temperature": 1.0,
                "thinkingConfig": ["thinkingBudget": 0]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FoodVisionError.networkError("No HTTP response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw FoodVisionError.apiError(httpResponse.statusCode, body)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else {
            throw FoodVisionError.malformedResponse("Could not extract text from Gemini response")
        }
        // Concatenate ALL parts — Gemini can split JSON across multiple parts
        let text = parts.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else {
            throw FoodVisionError.malformedResponse("Empty response from Gemini")
        }
        return text
    }

    // MARK: - Claude Text-Only Call

    private func callClaudeText(description: String, modelID: String = "claude-haiku-4-5-20251001") async throws -> String {
        let keyStore = APIKeyStore()
        let apiKey: String
        do { apiKey = try keyStore.retrieveClaudeKey() }
        catch { throw FoodVisionError.missingAPIKey("Claude") }

        guard let url = URL(string: Constants.API.claudeBaseURL) else {
            throw FoodVisionError.invalidURL
        }

        let userText = "Estimate the nutrition for this meal: \(description). Return JSON only, no explanation."

        let body: [String: Any] = [
            "model": modelID,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": [["type": "text", "text": userText]]
                ],
                ["role": "assistant", "content": "{"]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Constants.API.claudeAPIVersion, forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FoodVisionError.networkError("No HTTP response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? "unknown"
            throw FoodVisionError.apiError(httpResponse.statusCode, bodyStr)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String
        else {
            throw FoodVisionError.malformedResponse("Could not extract text from Claude response")
        }
        return "{" + text
    }

    // MARK: - On-Device Text Call (Apple Foundation Models)

    private func callOnDeviceText(description: String) async throws -> String {
        let userText = "Estimate the nutrition for this meal: \(description). Return JSON only, no explanation."
        let request = AIRequest(
            systemPrompt: systemPrompt,
            userMessage: userText,
            modelID: "apple-foundation-model",
            maxTokens: 4096,
            temperature: 0.7,
            stream: false
        )
        let response = try await OnDeviceProvider().complete(request)
        return response.text
    }

    // MARK: - Bedrock Text Call

    private func callBedrockText(description: String, modelID: String) async throws -> String {
        let keyStore = APIKeyStore()
        let userText = "Estimate the nutrition for this meal: \(description). Return JSON only, no explanation."
        let request = AIRequest(
            systemPrompt: systemPrompt,
            userMessage: userText,
            modelID: modelID,
            maxTokens: 4096,
            temperature: 0.7,
            stream: false
        )
        let response = try await BedrockProvider(keyStore: keyStore).complete(request)
        return response.text
    }

    // MARK: - Response Parsing

    private func parseResponse(_ text: String, imageData: Data?) throws -> ScannedMeal {
        logger.debug("Raw LLM response (\(text.count) chars): \(text.prefix(1000))")

        let cleaned = extractJSON(from: text)

        guard let jsonData = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else {
            logger.error("Failed to parse JSON. Cleaned text: \(cleaned.prefix(300))")
            throw FoodVisionError.malformedResponse("The AI returned an unexpected format. Please try again.")
        }

        let nutritionJSON = json["nutrition"] as? [String: Any] ?? [:]

        func doubleValue(_ key: String) -> Double {
            if let v = nutritionJSON[key] as? Double { return v }
            if let v = nutritionJSON[key] as? Int { return Double(v) }
            if let s = nutritionJSON[key] as? String, let d = Double(s) { return d }
            return 0
        }

        let nutrition = NutritionPayload(
            calories:           doubleValue("calories"),
            protein:            doubleValue("protein"),
            carbohydrates:      doubleValue("carbohydrates"),
            fat:                doubleValue("fat"),
            fiber:              doubleValue("fiber"),
            sugar:              doubleValue("sugar"),
            saturatedFat:       doubleValue("saturatedFat"),
            monounsaturatedFat: doubleValue("monounsaturatedFat"),
            polyunsaturatedFat: doubleValue("polyunsaturatedFat"),
            sodium:             doubleValue("sodium"),
            cholesterol:        doubleValue("cholesterol"),
            potassium:          doubleValue("potassium"),
            calcium:            doubleValue("calcium"),
            iron:               doubleValue("iron"),
            zinc:               doubleValue("zinc"),
            magnesium:          doubleValue("magnesium"),
            vitaminA:           doubleValue("vitaminA"),
            vitaminC:           doubleValue("vitaminC"),
            vitaminD:           doubleValue("vitaminD"),
            vitaminB6:          doubleValue("vitaminB6"),
            vitaminB12:         doubleValue("vitaminB12"),
            folate:             doubleValue("folate"),
            water:              doubleValue("water")
        )

        return ScannedMeal(
            foodName:    (json["foodName"]    as? String) ?? "Unknown Food",
            servingSize: (json["servingSize"] as? String) ?? "",
            confidence:  (json["confidence"]  as? String) ?? "low",
            nutrition:   nutrition,
            imageData:   imageData
        )
    }

    /// Extracts the first complete JSON object `{ ... }` from arbitrary LLM output using brace counting.
    private func extractJSON(from text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var depth = 0
        var startIdx: String.Index? = nil
        var endIdx: String.Index? = nil
        for idx in t.indices {
            let ch = t[idx]
            if ch == "{" {
                if depth == 0 { startIdx = idx }
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0 { endIdx = idx; break }
            }
        }
        if let s = startIdx, let e = endIdx, s <= e {
            let candidate = String(t[s...e])
            if isValidJSONObject(candidate) { return candidate }
        }
        return t
    }

    private func isValidJSONObject(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) != nil
    }
}

// MARK: - Errors

enum FoodVisionError: LocalizedError {
    case imageCompressionFailed
    case emptyDescription
    case noProviderAvailable
    case visionNotSupported(String)
    case missingAPIKey(String)
    case invalidURL
    case networkError(String)
    case apiError(Int, String)
    case malformedResponse(String)

    var errorDescription: String? {
        switch self {
        case .imageCompressionFailed:   return "Failed to process the image."
        case .emptyDescription:         return "Please describe your meal before analysing."
        case .noProviderAvailable:      return "No AI provider is configured. Add an API key in Settings."
        case .visionNotSupported(let msg): return msg
        case .missingAPIKey(let p):     return "No API key for \(p). Configure it in Settings."
        case .invalidURL:               return "Invalid API URL."
        case .networkError(let msg):    return "Network error: \(msg)"
        case .apiError(let code, let msg): return "API error \(code): \(msg)"
        case .malformedResponse(let d): return "Could not parse AI response: \(d)"
        }
    }
}

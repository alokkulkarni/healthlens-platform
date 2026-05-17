import Foundation
import CryptoKit
import OSLog

/// AWS Bedrock provider using SigV4 request signing.
/// Supports Claude models on Bedrock via InvokeModel and InvokeModelWithResponseStream.
struct BedrockProvider: AIProvider {
    let providerType: AIProviderType = .bedrock
    private let keyStore: APIKeyStore
    private let session: URLSession

    let availableModels: [AIModelDescriptor] = [
        AIModelDescriptor(
            id: "anthropic.claude-3-5-sonnet-20241022-v2:0",
            displayName: "Claude 3.5 Sonnet (Bedrock)",
            contextWindow: 200_000,
            supportsStreaming: true,
            isOnDevice: false,
            providerType: .bedrock
        ),
        AIModelDescriptor(
            id: "anthropic.claude-3-haiku-20240307-v1:0",
            displayName: "Claude 3 Haiku (Bedrock)",
            contextWindow: 200_000,
            supportsStreaming: true,
            isOnDevice: false,
            providerType: .bedrock
        ),
        AIModelDescriptor(
            id: "amazon.titan-text-express-v1",
            displayName: "Amazon Titan Express",
            contextWindow: 8_192,
            supportsStreaming: false,
            isOnDevice: false,
            providerType: .bedrock
        ),
    ]

    init(keyStore: APIKeyStore, session: URLSession = .shared) {
        self.keyStore = keyStore
        self.session = session
    }

    // MARK: - Complete

    func complete(_ request: AIRequest) async throws -> AIResponse {
        let creds = try getCredentials()
        let urlRequest = try await buildSignedRequest(
            request: request,
            credentials: creds,
            streaming: false
        )
        let start = Date()
        let (data, response) = try await session.data(for: urlRequest)
        let latency = Date().timeIntervalSince(start) * 1000
        try validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(BedrockClaudeResponse.self, from: data)
        return AIResponse(
            text: decoded.content.first?.text ?? "",
            inputTokens: decoded.usage?.inputTokens ?? 0,
            outputTokens: decoded.usage?.outputTokens ?? 0,
            modelID: request.modelID,
            finishReason: decoded.stopReason ?? "end_turn",
            latencyMS: latency,
            rawJSON: data
        )
    }

    // MARK: - Stream

    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let creds = try getCredentials()
                    let urlRequest = try await buildSignedRequest(
                        request: request,
                        credentials: creds,
                        streaming: true
                    )
                    let (bytes, response) = try await session.bytes(for: urlRequest)

                    if let httpResponse = response as? HTTPURLResponse,
                       !(200...299).contains(httpResponse.statusCode) {
                        var errorData = Data()
                        for try await byte in bytes {
                            errorData.append(byte)
                            if errorData.count > 4096 { break }
                        }
                        let body = String(data: errorData, encoding: .utf8) ?? ""
                        if httpResponse.statusCode == 429 {
                            continuation.finish(throwing: AIError.rateLimited)
                        } else {
                            continuation.finish(throwing: AIError.providerError(
                                statusCode: httpResponse.statusCode,
                                message: body.isEmpty ? "HTTP \(httpResponse.statusCode)" : body
                            ))
                        }
                        return
                    }

                    // Bedrock uses event-stream framing
                    var buffer = Data()
                    for try await byte in bytes {
                        buffer.append(byte)
                        // Try to decode accumulated buffer
                        if let text = StreamingDecoder.extractBedrockText(from: buffer) {
                            continuation.yield(text)
                            buffer = Data()
                        }
                    }
                    continuation.finish()
                } catch let error as AIError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: AIError.networkError(error))
                }
            }
        }
    }

    // MARK: - Helpers

    private func getCredentials() throws -> BedrockCredentials {
        do {
            return try keyStore.retrieveBedrockCredentials()
        } catch {
            throw AIError.missingAPIKey(.bedrock)
        }
    }

    private func buildSignedRequest(
        request: AIRequest,
        credentials: BedrockCredentials,
        streaming: Bool
    ) async throws -> URLRequest {
        let region = credentials.region.isEmpty
            ? Constants.API.bedrockRegion
            : credentials.region
        let service = "bedrock"
        let action = streaming ? "invoke-with-response-stream" : "invoke"
        let urlString = "https://bedrock-runtime.\(region).amazonaws.com/model/\(request.modelID)/\(action)"

        guard let url = URL(string: urlString) else {
            throw AIError.invalidResponse("Invalid Bedrock URL")
        }

        // Build Claude-format body for Bedrock
        let body = BedrockClaudeRequest(
            anthropicVersion: "bedrock-2023-05-31",
            maxTokens: request.maxTokens,
            system: request.systemPrompt,
            messages: [BedrockMessage(role: "user", content: request.userMessage)],
            temperature: request.temperature
        )
        let bodyData = try JSONEncoder().encode(body)

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = bodyData
        urlRequest.timeoutInterval = 120

        // Apply SigV4 signing
        try SigV4Signer.sign(
            request: &urlRequest,
            bodyData: bodyData,
            service: service,
            region: region,
            accessKey: credentials.accessKeyID,
            secretKey: credentials.secretAccessKey,
            sessionToken: credentials.sessionToken
        )

        return urlRequest
    }
}

// MARK: - SigV4 Signer

enum SigV4Signer {
    static func sign(
        request: inout URLRequest,
        bodyData: Data,
        service: String,
        region: String,
        accessKey: String,
        secretKey: String,
        sessionToken: String?
    ) throws {
        let now = Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        let amzDate = now.sigV4DateString
        let dateStamp = now.sigV4DateStamp

        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        if let token = sessionToken {
            request.setValue(token, forHTTPHeaderField: "x-amz-security-token")
        }

        let bodyHash = SHA256.hash(data: bodyData)
            .compactMap { String(format: "%02x", $0) }.joined()
        request.setValue(bodyHash, forHTTPHeaderField: "x-amz-content-sha256")

        let host = request.url?.host ?? ""
        request.setValue(host, forHTTPHeaderField: "host")

        // Canonical request
        let method = request.httpMethod ?? "POST"
        let path = request.url?.path ?? "/"
        let query = request.url?.query ?? ""

        let signedHeaders = ["content-type", "host", "x-amz-content-sha256", "x-amz-date"]
            + (sessionToken != nil ? ["x-amz-security-token"] : [])
        let signedHeadersString = signedHeaders.sorted().joined(separator: ";")

        var canonicalHeaders = ""
        for header in signedHeaders.sorted() {
            let value = request.value(forHTTPHeaderField: header) ?? ""
            canonicalHeaders += "\(header):\(value)\n"
        }

        let canonicalRequest = [method, path, query, canonicalHeaders, signedHeadersString, bodyHash]
            .joined(separator: "\n")

        // String to sign
        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        guard let canonicalRequestData = canonicalRequest.data(using: .utf8) else {
            throw AIError.invalidResponse("SigV4: failed to encode canonical request")
        }
        let canonicalRequestHash = SHA256.hash(data: canonicalRequestData)
            .compactMap { String(format: "%02x", $0) }.joined()
        let stringToSign = "AWS4-HMAC-SHA256\n\(amzDate)\n\(credentialScope)\n\(canonicalRequestHash)"

        // Signing key
        let signingKey = try deriveSigningKey(
            secretKey: secretKey,
            dateStamp: dateStamp,
            region: region,
            service: service
        )

        // Signature
        guard let stringToSignData = stringToSign.data(using: .utf8) else {
            throw AIError.invalidResponse("SigV4: failed to encode string-to-sign")
        }
        let signature = HMAC<SHA256>.authenticationCode(
            for: stringToSignData,
            using: signingKey
        )
        .compactMap { String(format: "%02x", $0) }.joined()

        let authHeader = "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(credentialScope), SignedHeaders=\(signedHeadersString), Signature=\(signature)"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
    }

    private static func deriveSigningKey(
        secretKey: String,
        dateStamp: String,
        region: String,
        service: String
    ) throws -> SymmetricKey {
        guard
            let kSecretData = ("AWS4" + secretKey).data(using: .utf8),
            let kDateData = dateStamp.data(using: .utf8),
            let kRegionData = region.data(using: .utf8),
            let kServiceData = service.data(using: .utf8),
            let kSigningData = "aws4_request".data(using: .utf8)
        else {
            throw AIError.invalidResponse("SigV4: failed to encode signing key components")
        }
        let kSecret = SymmetricKey(data: kSecretData)
        let kDate = HMAC<SHA256>.authenticationCode(for: kDateData, using: kSecret)
        let kRegion = HMAC<SHA256>.authenticationCode(for: kRegionData, using: SymmetricKey(data: kDate))
        let kService = HMAC<SHA256>.authenticationCode(for: kServiceData, using: SymmetricKey(data: kRegion))
        let kSigning = HMAC<SHA256>.authenticationCode(for: kSigningData, using: SymmetricKey(data: kService))
        return SymmetricKey(data: kSigning)
    }
}

private extension Date {
    var sigV4DateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: self)
    }

    var sigV4DateStamp: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: self)
    }
}

// MARK: - Codable types

private struct BedrockClaudeRequest: Encodable {
    let anthropicVersion: String
    let maxTokens: Int
    let system: String
    let messages: [BedrockMessage]
    let temperature: Double

    enum CodingKeys: String, CodingKey {
        case anthropicVersion = "anthropic_version"
        case maxTokens = "max_tokens"
        case system, messages, temperature
    }
}

private struct BedrockMessage: Encodable {
    let role: String
    let content: String
}

private struct BedrockClaudeResponse: Decodable {
    let content: [ContentBlock]
    let usage: Usage?
    let stopReason: String?

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    struct Usage: Decodable {
        let inputTokens: Int
        let outputTokens: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    enum CodingKeys: String, CodingKey {
        case content, usage
        case stopReason = "stop_reason"
    }
}

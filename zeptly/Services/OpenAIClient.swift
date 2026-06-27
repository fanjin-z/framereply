//
//  OpenAIClient.swift
//  zeptly
//

import Foundation

struct OpenAIClient: ProviderValidator {
    private let baseURL = URL(string: "https://api.openai.com/v1")!
    private let session: URLSession
    private let validationMaxOutputTokens = 16

    init(session: URLSession = .shared) {
        self.session = session
    }

    func validate(apiKey: String, model: ProviderModel) async throws {
        var request = URLRequest(url: baseURL.appending(path: "responses"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            OpenAIResponseRequest(
                model: model.rawValue,
                input: "Reply exactly: OK.",
                maxOutputTokens: validationMaxOutputTokens,
                reasoning: OpenAIReasoning(effort: "none")
            )
        )

        let (data, response) = try await perform(request)
        try validateHTTPResponse(response, data: data)

        let completion: OpenAIResponse
        do {
            completion = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        } catch {
            throw ProviderConnectionError.invalidResponse("OpenAI returned an unexpected response.")
        }

        guard
            completion.id.isEmpty == false,
            completion.status == "completed",
            completion.hasTextOutput
        else {
            throw ProviderConnectionError.invalidResponse("OpenAI did not return a completed text response.")
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw ProviderConnectionError.networkFailure(error.localizedDescription)
        } catch {
            throw ProviderConnectionError.networkFailure("Could not reach OpenAI. Check your network and try again.")
        }
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderConnectionError.invalidResponse("OpenAI returned an invalid HTTP response.")
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 401:
            throw ProviderConnectionError.invalidKey
        case 429:
            if openAIError(from: data)?.code == "insufficient_quota" {
                throw ProviderConnectionError.insufficientBalance
            }
            throw ProviderConnectionError.rateLimited
        case 500..<600:
            throw ProviderConnectionError.providerUnavailable
        default:
            throw ProviderConnectionError.invalidResponse(
                openAIError(from: data)?.message
                    ?? "OpenAI returned HTTP \(httpResponse.statusCode)."
            )
        }
    }

    private func openAIError(from data: Data) -> OpenAIError? {
        try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data).error
    }
}

private struct OpenAIResponseRequest: Encodable {
    let model: String
    let input: String
    let maxOutputTokens: Int
    let reasoning: OpenAIReasoning

    private enum CodingKeys: String, CodingKey {
        case model
        case input
        case maxOutputTokens = "max_output_tokens"
        case reasoning
    }
}

private struct OpenAIReasoning: Encodable {
    let effort: String
}

private struct OpenAIResponse: Decodable {
    let id: String
    let status: String
    let output: [OpenAIOutput]

    var hasTextOutput: Bool {
        output.contains { item in
            item.type == "message"
                && item.content.contains { content in
                    content.type == "output_text"
                        && content.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                }
        }
    }
}

private struct OpenAIOutput: Decodable {
    let type: String
    let content: [OpenAIOutputContent]

    private enum CodingKeys: String, CodingKey {
        case type
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        content = try container.decodeIfPresent([OpenAIOutputContent].self, forKey: .content) ?? []
    }
}

private struct OpenAIOutputContent: Decodable {
    let type: String
    let text: String?
}

private struct OpenAIErrorResponse: Decodable {
    let error: OpenAIError
}

private struct OpenAIError: Decodable {
    let code: String?
    let message: String
}

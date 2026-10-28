// Gemma via llama.cpp (il nostro llama-server, Sources/App/Engines/LlamaServer.swift) o via Ollama: tutti e due
// espongono su localhost lo stesso endpoint compatibile con OpenAI, POST /v1/chat/completions. Il testo va solo a
// 127.0.0.1, mai in rete. Il seguito arriva a pezzi (stream: true, righe SSE "data: {...}" fino a "data: [DONE]").
// Un motore per server avviato: indirizzo e nome del modello non cambiano, se il server cambia se ne crea un altro.

import Foundation

final class LlamaEngine: CompletionEngine, @unchecked Sendable {
    let kind = EngineKind.gemma
    let displayName: String
    /// Gemma ha una finestra ampia (il server parte con 2048 token): i 2000 caratteri letti dal campo ci stanno.
    let contextLimit = TextContext.maxBefore
    let baseURL: URL
    /// Il campo "model" della richiesta: per Ollama il nome del modello, per llama-server è indifferente.
    let model: String

    var unavailableReason: String? { nil }

    init(baseURL: URL, model: String, displayName: String) {
        self.baseURL = baseURL
        self.model = model
        self.displayName = displayName
    }

    func complete(_ request: CompletionRequest, partial: @escaping @Sendable (String) -> Void) async throws -> String {
        let body = Self.body(model: model, system: Prompting.completionInstructions(request),
                             user: Prompting.completionPrompt(request), maxTokens: request.length.maxTokens,
                             temperature: 0.2, stream: true)
        let (bytes, response) = try await LocalHTTP.session.bytes(for: chatRequest(body))
        try Self.check(response)
        var text = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            if let message = Self.errorMessage(payload) { throw EngineError(message) }
            guard let piece = Self.content(payload), !piece.isEmpty else { continue }
            text += piece
            partial(text)
            // Un a capo dopo il primo pezzo vuol dire che il seguito è finito: si smette di leggere.
            if AppleEngine.endsLine(text) { break }
        }
        return text
    }

    func rewrite(_ text: String, instruction: String, language: String?) async throws -> String {
        let body = Self.body(model: model, system: Prompting.rewriteInstructions(instruction, language: language),
                             user: Prompting.rewritePrompt(text), maxTokens: 600, temperature: 0.3, stream: false)
        var request = chatRequest(body)
        request.timeoutInterval = 30   // una riscrittura lunga può richiedere più dei 10 secondi del seguito
        let (data, response) = try await LocalHTTP.session.data(for: request)
        try Self.check(response)
        let payload = String(decoding: data, as: UTF8.self)
        if let message = Self.errorMessage(payload) { throw EngineError(message) }
        guard let content = Self.content(payload) else { throw EngineError(L("Il modello non ha risposto.")) }
        return content
    }

    // MARK: - Richiesta e risposta

    private func chatRequest(_ body: Data) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = body
        return request
    }

    private static func body(model: String, system: String, user: String, maxTokens: Int, temperature: Double,
                             stream: Bool) -> Data {
        let messages: [[String: String]] = [
            ["role": "system", "content": system],
            ["role": "user", "content": user],
        ]
        var object: [String: Any] = [:]
        object["model"] = model
        object["messages"] = messages
        object["max_tokens"] = maxTokens
        object["temperature"] = temperature
        object["stream"] = stream
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    private static func check(_ response: URLResponse) throws {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            if code == 404 { throw EngineError(L("Il modello non c'è sul server (se usi Ollama, scaricalo con ollama pull).")) }
            throw EngineError(L("Il server di Gemma ha risposto con un errore (%d).", code))
        }
    }

    /// Il testo di un pezzo (choices[0].delta.content) o di una risposta intera (choices[0].message.content).
    static func content(_ json: String) -> String? {
        guard let object = parse(json),
              let choices = object["choices"] as? [[String: Any]], let first = choices.first else { return nil }
        if let delta = first["delta"] as? [String: Any], let text = delta["content"] as? String { return text }
        if let message = first["message"] as? [String: Any], let text = message["content"] as? String { return text }
        return nil
    }

    /// Il messaggio d'errore del server, se la risposta è un errore ({"error": {"message": …}}).
    static func errorMessage(_ json: String) -> String? {
        guard let object = parse(json), let error = object["error"] else { return nil }
        if let detail = error as? [String: Any], let message = detail["message"] as? String { return message }
        if let message = error as? String { return message }
        return L("Il server di Gemma ha risposto con un errore.")
    }

    private static func parse(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// Le chiamate a localhost: una sessione senza cache né cookie, con tempi corti. Solo 127.0.0.1.
enum LocalHTTP {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30   // ogni richiesta mette il suo, più corto (10 s per il seguito)
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = false
        configuration.connectionProxyDictionary = [:]
        return URLSession(configuration: configuration)
    }()

    /// Vero se GET `url` risponde 200 entro `timeout` secondi.
    static func isOK(_ url: URL, timeout: TimeInterval = 2) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        guard let result = try? await session.data(for: request) else { return false }
        return (result.1 as? HTTPURLResponse)?.statusCode == 200
    }

    /// I modelli che Ollama ha già scaricato (GET /api/tags), nil se Ollama non è aperto.
    static func ollamaModels(timeout: TimeInterval = 1.5) async -> [String]? {
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        guard let result = try? await session.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        guard let object = (try? JSONSerialization.jsonObject(with: result.0)) as? [String: Any],
              let models = object["models"] as? [[String: Any]] else { return [] }
        var names: [String] = []
        for model in models {
            if let name = model["name"] as? String { names.append(name) }
            if let other = model["model"] as? String, !names.contains(other) { names.append(other) }
        }
        return names
    }

    static let ollamaBase = URL(string: "http://127.0.0.1:11434")!
}

// Gemma via llama.cpp (il nostro llama-server, Sources/App/Engines/LlamaServer.swift) o via Ollama: tutti e due
// espongono su localhost lo stesso endpoint compatibile con OpenAI, POST /v1/chat/completions. Il testo va solo a
// 127.0.0.1, mai in rete. Il seguito arriva a pezzi (stream: true, righe SSE "data: {...}" fino a "data: [DONE]").
// Un motore per server avviato: indirizzo e nome del modello non cambiano, se il server cambia se ne crea un altro.
// Con un modello base (rawCompletion) si usa invece l'endpoint nativo /completion di llama-server: il prompt è il
// testo prima del cursore e il modello lo continua così com'è, senza istruzioni. Per riscrivere serve un modello istruito.

import Foundation

/// I tempi che llama-server mette nell'ultimo pezzo della risposta ("timings"): quanti token di prompt ha elaborato,
/// quanti ha ripreso dalla cache e quanto ci ha messo. Solo numeri, per la diagnostica.
struct LlamaTimings: Equatable, Sendable {
    var promptTokens: Int
    var cachedTokens: Int?
    var promptMs: Double
    var predictedTokens: Int
    var predictedMs: Double

    init?(_ chunk: [String: Any]) {
        guard let t = chunk["timings"] as? [String: Any] else { return nil }
        func number(_ key: String) -> Double? { (t[key] as? NSNumber)?.doubleValue }
        guard let promptN = number("prompt_n"), let promptMs = number("prompt_ms") else { return nil }
        promptTokens = Int(promptN)
        self.promptMs = promptMs
        predictedTokens = Int(number("predicted_n") ?? 0)
        predictedMs = number("predicted_ms") ?? 0
        if let cache = number("cache_n") { cachedTokens = Int(cache) }
        else if let cached = (chunk["tokens_cached"] as? NSNumber)?.intValue { cachedTokens = Swift.max(0, cached - promptTokens) }
    }
}

final class LlamaEngine: CompletionEngine, @unchecked Sendable {
    let kind = EngineKind.gemma
    let displayName: String
    /// Circa 1.200 caratteri (300-400 token): abbastanza per il tono e il filo del discorso, pochi da rielaborare
    /// quando la cache del prompt non basta. Il server parte con 2048 token.
    let contextLimit = 1200
    let baseURL: URL
    /// Il campo "model" della richiesta: per Ollama il nome del modello, per llama-server è indifferente.
    let model: String
    /// Modello base: continuazione pura via /completion (solo con il nostro llama-server).
    let rawCompletion: Bool

    var unavailableReason: String? { nil }

    private let lock = NSLock()
    private var timings: LlamaTimings?
    /// I tempi dell'ultima risposta arrivata fino in fondo, se il server li ha dati.
    var lastTimings: LlamaTimings? { lock.withLock { timings } }
    private func note(_ chunk: [String: Any]) {
        guard let t = LlamaTimings(chunk) else { return }
        lock.withLock { timings = t }
    }

    init(baseURL: URL, model: String, displayName: String, rawCompletion: Bool = false) {
        self.baseURL = baseURL
        self.model = model
        self.displayName = displayName
        self.rawCompletion = rawCompletion
    }

    func complete(_ request: CompletionRequest, partial: @escaping @Sendable (String) -> Void) async throws -> String {
        lock.withLock { timings = nil }
        if rawCompletion { return try await completeRaw(request, partial: partial) }
        let body = Self.body(model: model, system: Prompting.completionInstructions(request),
                             user: Prompting.completionPrompt(request), maxTokens: request.maxTokens,
                             temperature: 0.2, stream: true)
        let (bytes, response) = try await LocalHTTP.session.bytes(for: chatRequest(body))
        try Self.check(response)
        var text = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            if let message = Self.errorMessage(payload) { throw EngineError(message) }
            if payload.contains("\"timings\""), let chunk = Self.parse(payload) { note(chunk) }
            guard let piece = Self.content(payload), !piece.isEmpty else { continue }
            text += piece
            partial(text)
            // Un a capo dopo il primo pezzo vuol dire che il seguito è finito: si smette di leggere.
            if AppleEngine.endsLine(text) { break }
        }
        return text
    }

    /// Modello base: il prompt è il testo stesso, il modello lo continua. Si ferma a fine riga.
    private func completeRaw(_ request: CompletionRequest, partial: @escaping @Sendable (String) -> Void) async throws -> String {
        var object: [String: Any] = [:]
        object["prompt"] = Prompting.rawPrompt(request)
        object["n_predict"] = request.maxTokens
        // La parola più probabile, sempre: suggerimenti stabili, e la probabilità di ogni token per decidere dove
        // fermarsi (ConfidenceStop). Niente stop a "\n": dopo una frase finita il modello va spesso a capo e il seguito
        // è la riga dopo (Prompting.cleanCompletion la prende); ci si ferma a fine riga, sotto.
        object["temperature"] = 0
        object["repeat_penalty"] = 1.1
        object["n_probs"] = 1
        object["cache_prompt"] = true
        object["stream"] = true
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("completion"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 10
        urlRequest.httpBody = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        let (bytes, response) = try await LocalHTTP.session.bytes(for: urlRequest)
        try Self.check(response)
        var stop = ConfidenceStop(length: request.length, maxWords: request.maxWords)
        var natural = false
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            if let message = Self.errorMessage(payload) { throw EngineError(message) }
            guard let chunk = Self.parse(payload) else { continue }
            note(chunk)
            if let piece = chunk["content"] as? String, !piece.isEmpty {
                if stop.add(piece, probability: Self.probability(chunk)) { break }
                // Si mostra solo quello di cui il modello è già sicuro: niente parole che compaiono e spariscono.
                if !stop.confident.isEmpty { partial(stop.confident) }
                // Finita la riga (dopo un eventuale a capo iniziale), il seguito è completo.
                if AppleEngine.endsLine(stop.text) { natural = true; break }
            }
            if (chunk["stop"] as? Bool) == true {
                natural = (chunk["stop_type"] as? String) != "limit"
                break
            }
        }
        return stop.result(natural: natural)
    }

    /// La probabilità del pezzo (il prodotto di quelle dei suoi token), da "completion_probabilities" di llama-server:
    /// "logprob" nelle versioni nuove, "prob" in quelle vecchie. nil se il server non la dà.
    static func probability(_ chunk: [String: Any]) -> Double? {
        guard let tokens = chunk["completion_probabilities"] as? [[String: Any]], !tokens.isEmpty else { return nil }
        var product = 1.0
        for token in tokens {
            if let logprob = (token["logprob"] as? NSNumber)?.doubleValue { product *= exp(logprob) }
            else if let prob = (token["prob"] as? NSNumber)?.doubleValue { product *= prob }
            else if let probs = token["probs"] as? [[String: Any]], let first = probs.first,
                    let prob = (first["prob"] as? NSNumber)?.doubleValue { product *= prob }
            else { return nil }
        }
        return product
    }

    func rewrite(_ text: String, instruction: String, language: String?) async throws -> String {
        if rawCompletion {
            throw EngineError(L("Questo modello continua il testo ma non segue istruzioni: per riscrivere scegli un modello istruito o Apple Intelligence."))
        }
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
        object["cache_prompt"] = true   // llama-server: riusa il prompt già elaborato (Ollama ignora il campo)
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

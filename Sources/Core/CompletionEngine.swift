// Il contratto dei motori: dato il contesto, il seguito (anche a pezzi, man mano che il modello lo scrive); dato un
// testo e un'istruzione, la riscrittura. Apple Intelligence (Sources/App/Engines/AppleEngine.swift) e Gemma via
// llama.cpp o Ollama (Sources/App/Engines/LlamaEngine.swift), con la stessa interfaccia.

import Foundation

enum EngineKind: String, CaseIterable, Codable, Identifiable {
    case apple, gemma
    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: "Apple Intelligence"
        case .gemma: "Gemma"
        }
    }
}

struct EngineError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

protocol CompletionEngine: AnyObject, Sendable {
    var kind: EngineKind { get }
    /// Il nome da mostrare: "Apple Intelligence", "Gemma 3 1B".
    var displayName: String { get }
    /// nil se il motore si può usare adesso, altrimenti il perché (da mostrare).
    var unavailableReason: String? { get }
    /// Quanti caratteri prima del cursore legge il modello al massimo (il resto si taglia a confine di parola).
    var contextLimit: Int { get }
    /// Il seguito grezzo proposto dal modello; lo pulisce `Prompting.cleanCompletion`. `partial` riceve il testo
    /// accumulato finora a ogni pezzo che arriva (da un thread qualunque).
    func complete(_ request: CompletionRequest, partial: @escaping @Sendable (String) -> Void) async throws -> String
    /// Il testo riscritto secondo l'istruzione; lo pulisce `Prompting.cleanRewrite`.
    func rewrite(_ text: String, instruction: String, language: String?) async throws -> String
}

extension CompletionEngine {
    /// Il seguito tutto insieme, senza i pezzi intermedi.
    func complete(_ request: CompletionRequest) async throws -> String {
        try await complete(request, partial: { _ in })
    }
}

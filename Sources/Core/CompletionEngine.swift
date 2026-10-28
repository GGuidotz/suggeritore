// Il contratto dei motori: dato il contesto, il seguito; dato un testo e un'istruzione, la riscrittura. Oggi Apple
// Intelligence (Sources/App/Engines/AppleEngine.swift); domani Gemma via llama.cpp con la stessa interfaccia.

import Foundation

enum EngineKind: String, CaseIterable, Codable, Identifiable {
    case apple
    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: "Apple Intelligence"
        }
    }
}

struct EngineError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

protocol CompletionEngine: AnyObject {
    var kind: EngineKind { get }
    /// nil se il motore si può usare adesso, altrimenti il perché (da mostrare).
    var unavailableReason: String? { get }
    /// Il seguito grezzo proposto dal modello; lo pulisce `Prompting.cleanCompletion`.
    func complete(_ request: CompletionRequest) async throws -> String
    /// Il testo riscritto secondo l'istruzione; lo pulisce `Prompting.cleanRewrite`.
    func rewrite(_ text: String, instruction: String, language: String?) async throws -> String
}

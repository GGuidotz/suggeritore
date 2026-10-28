// Apple Intelligence (FoundationModels): il modello sul Mac. Niente rete, niente dati che escono. Una sessione nuova
// per ogni richiesta (le richieste sono indipendenti e la finestra del modello è piccola), istruzioni e prompt da
// Sources/Core/Prompting.swift. Contesto corto (700 caratteri) e scelta "greedy": risponde prima e divaga meno. Il
// seguito arriva a pezzi (streamResponse). Senza il framework o senza Apple Intelligence attiva dice perché non c'è.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

final class AppleEngine: CompletionEngine, @unchecked Sendable {
    let kind = EngineKind.apple
    let displayName = "Apple Intelligence"
    /// Il modello di Apple è lento con i contesti lunghi: gli ultimi 700 caratteri bastano per il seguito.
    let contextLimit = 700

    /// nil se Apple Intelligence si può usare adesso, altrimenti perché no.
    var unavailableReason: String? { Self.unavailableReason }

    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.deviceNotEligible):
                return L("Questo Mac non supporta Apple Intelligence.")
            case .unavailable(.appleIntelligenceNotEnabled):
                return L("Apple Intelligence è spenta: Impostazioni di Sistema › Apple Intelligence e Siri.")
            case .unavailable(.modelNotReady):
                return L("Il modello di Apple Intelligence si sta ancora scaricando.")
            default:
                return L("Apple Intelligence non è disponibile adesso.")
            }
        }
        #endif
        return L("Serve macOS 26 con Apple Intelligence.")
    }

    /// Carica il modello in anticipo: il primo suggerimento arriva prima.
    func prewarm() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), Self.unavailableReason == nil {
            let session = LanguageModelSession(instructions: "You are an autocomplete engine. Output only the continuation.")
            session.prewarm()
        }
        #endif
    }

    func complete(_ request: CompletionRequest, partial: @escaping @Sendable (String) -> Void) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard Self.unavailableReason == nil else { throw EngineError(Self.unavailableReason ?? "") }
            let session = LanguageModelSession(instructions: Prompting.completionInstructions(request))
            // Greedy: sempre la parola più probabile, niente temperatura.
            let options = GenerationOptions(samplingMode: .greedy, temperature: nil,
                                            maximumResponseTokens: request.length.maxTokens)
            // Da verificare sul Mac: in macOS 26 ogni elemento dello stream è uno snapshot con `.content` (per le
            // risposte testuali una String con tutto il testo scritto finora).
            let stream = session.streamResponse(to: Prompting.completionPrompt(request), options: options)
            var text = ""
            for try await snapshot in stream {
                text = snapshot.content
                partial(text)
                // Un a capo dopo il primo pezzo vuol dire che il seguito è finito: inutile aspettare il resto.
                if Self.endsLine(text) { break }
            }
            return text
        }
        #endif
        throw EngineError(Self.unavailableReason ?? L("Apple Intelligence non è disponibile adesso."))
    }

    func rewrite(_ text: String, instruction: String, language: String?) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard Self.unavailableReason == nil else { throw EngineError(Self.unavailableReason ?? "") }
            let session = LanguageModelSession(instructions: Prompting.rewriteInstructions(instruction, language: language))
            let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: 600)
            let response = try await session.respond(to: Prompting.rewritePrompt(text), options: options)
            return response.content
        }
        #endif
        throw EngineError(Self.unavailableReason ?? L("Apple Intelligence non è disponibile adesso."))
    }

    /// Vero se il testo, tolti gli spazi iniziali, contiene già un a capo.
    static func endsLine(_ text: String) -> Bool {
        text.drop(while: { $0.isWhitespace || $0.isNewline }).contains(where: { $0.isNewline })
    }
}

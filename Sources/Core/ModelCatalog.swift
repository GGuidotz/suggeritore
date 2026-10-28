// I modelli che Suggeritore sa avviare con llama.cpp (repository Hugging Face con il file GGUF, scaricato al primo
// avvio nella cache di llama.cpp) o chiedere a Ollama (nome del modello). Tre Gemma 3 pronti, più quelli che aggiungi
// tu dalle impostazioni. Solo Foundation.

import Foundation

struct ModelEntry: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var title: String
    /// Il repository Hugging Face per `llama-server -hf`, nil se il modello si usa solo con Ollama.
    var hfRepo: String?
    /// Il nome in Ollama ("gemma3:1b"), nil se il modello si usa solo con llama.cpp.
    var ollamaName: String?
    /// Quanto pesa da scaricare, in parole ("circa 0,8 GB"); vuoto se non si sa.
    var sizeHint: String
    var isBuiltIn: Bool
    /// Il modello che consigliamo.
    var isRecommended: Bool = false

    /// "Gemma 3 1B · circa 0,8 GB"
    var titleWithSize: String { sizeHint.isEmpty ? title : "\(title) · \(sizeHint)" }
}

enum ModelCatalog {
    static let defaultID = "gemma3-1b"

    /// I modelli pronti. Nomi dei repository da verificare sul Mac: ggml-org pubblica i GGUF ufficiali di Gemma 3
    /// (gemma-3-1b-it-GGUF, gemma-3-4b-it-GGUF, gemma-3-12b-it-GGUF); llama.cpp sceglie da solo la quantizzazione.
    static var builtIn: [ModelEntry] {
        [
            ModelEntry(id: "gemma3-1b", title: "Gemma 3 1B", hfRepo: "ggml-org/gemma-3-1b-it-GGUF", ollamaName: "gemma3:1b",
                       sizeHint: L("circa 0,8 GB"), isBuiltIn: true, isRecommended: true),
            ModelEntry(id: "gemma3-4b", title: "Gemma 3 4B", hfRepo: "ggml-org/gemma-3-4b-it-GGUF", ollamaName: "gemma3:4b",
                       sizeHint: L("circa 2,5 GB"), isBuiltIn: true),
            ModelEntry(id: "gemma3-12b", title: "Gemma 3 12B", hfRepo: "ggml-org/gemma-3-12b-it-GGUF", ollamaName: "gemma3:12b",
                       sizeHint: L("circa 7 GB"), isBuiltIn: true),
        ]
    }

    /// I pronti, poi i tuoi.
    static func all(custom: [ModelEntry]) -> [ModelEntry] {
        var out = builtIn
        for entry in custom where !out.contains(where: { $0.id == entry.id }) {
            out.append(entry)
        }
        return out
    }

    /// Il modello con quell'id; se non c'è più (un personalizzato rimosso), quello consigliato.
    static func entry(id: String, custom: [ModelEntry]) -> ModelEntry {
        let everything = all(custom: custom)
        if let found = everything.first(where: { $0.id == id }) { return found }
        return everything.first(where: { $0.id == defaultID }) ?? everything[0]
    }

    /// Una voce personalizzata: un nome e almeno uno tra repository Hugging Face e nome Ollama. nil se manca tutto.
    static func custom(title: String, hfRepo: String, ollamaName: String) -> ModelEntry? {
        let repo = hfRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        let ollama = ollamaName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repo.isEmpty || !ollama.isEmpty else { return nil }
        guard !repo.contains(" "), !ollama.contains(" ") else { return nil }
        var name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = repo.isEmpty ? ollama : repo }
        return ModelEntry(id: "custom-" + UUID().uuidString.lowercased(), title: name,
                          hfRepo: repo.isEmpty ? nil : repo, ollamaName: ollama.isEmpty ? nil : ollama,
                          sizeHint: "", isBuiltIn: false)
    }
}

// Il motore senza modello: la memoria delle frasi accettate e poche formule fisse (chiusure di lettera e email).
// Risponde subito, a ogni pausa, prima che il modello venga interpellato.

import Foundation

final class RulesEngine {
    let memory: PhraseMemory

    init(memory: PhraseMemory) { self.memory = memory }

    /// Formule: la fine del testo (minuscolo) → il seguito con lo spazio davanti.
    static let phrases: [(trigger: String, continuation: String)] = [
        ("cordiali", " saluti,"), ("distinti", " saluti,"), ("un caro", " saluto,"), ("cari", " saluti,"),
        ("resto a", " disposizione"), ("restiamo a", " disposizione"), ("in attesa di un", " suo riscontro,"),
        ("grazie in", " anticipo"), ("grazie per", " la disponibilità"), ("buona", " giornata"),
        ("kind", " regards,"), ("best", " regards,"), ("looking forward to", " hearing from you"),
        ("thank you in", " advance"), ("please let me", " know"), ("feel free to", " reach out"),
    ]

    func suggestion(for context: TextContext, useMemory: Bool) -> Suggestion? {
        if useMemory, let remembered = memory.suggestion(before: context.before) {
            return Suggestion(text: remembered, source: .memory)
        }
        let endsWithSpace = context.before.last?.isWhitespace == true
        let tail = context.before.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression).lowercased()
        for phrase in Self.phrases where tail.hasSuffix(phrase.trigger) {
            // A confine di parola: prima della formula c'è spazio, a capo o niente.
            let start = tail.index(tail.endIndex, offsetBy: -phrase.trigger.count)
            if start > tail.startIndex, tail[tail.index(before: start)].isLetter { continue }
            // Il testo dopo il cursore (metà riga) non deve già contenere il seguito.
            if !context.after.isEmpty, context.after.lowercased().hasPrefix(phrase.continuation.trimmingCharacters(in: .whitespaces)) { continue }
            let text = endsWithSpace ? String(phrase.continuation.drop(while: { $0 == " " })) : phrase.continuation
            return Suggestion(text: text, source: .rules)
        }
        return nil
    }
}

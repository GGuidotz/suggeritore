// Il refuso sospetto: se la parola che stai scrivendo ha già un errore, allungarla non aiuta. Il controllo
// ortografico di macOS dice se il pezzo di parola è sbagliato e se esiste una parola che comincia così; se è sbagliato
// e nessuna parola comincia così, niente suggerimento. Guarda solo la parola corrente: non è un correttore.

import AppKit

@MainActor
enum SpellGuard {
    private static let tag = NSSpellChecker.uniqueSpellDocumentTag()

    /// Vero se `partial` (almeno 4 lettere) sembra già sbagliato. `language`: "it", "en", nil per quella di sistema.
    static func looksMistyped(_ partial: String, language: String?) -> Bool {
        guard partial.count >= 4, partial.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" }) else { return false }
        let checker = NSSpellChecker.shared
        let lang = language.flatMap { code in checker.availableLanguages.first { $0 == code || $0.hasPrefix(code + "_") } }
        var words = 0
        let miss = checker.checkSpelling(of: partial, startingAt: 0, language: lang, wrap: false,
                                         inSpellDocumentWithTag: tag, wordCount: &words)
        guard miss.location != NSNotFound else { return false }   // è già una parola intera: va bene
        let range = NSRange(location: 0, length: (partial as NSString).length)
        let completions = checker.completions(forPartialWordRange: range, in: partial, language: lang,
                                              inSpellDocumentWithTag: tag) ?? []
        return completions.isEmpty
    }
}

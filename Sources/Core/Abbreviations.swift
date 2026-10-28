// Le abbreviazioni che si espandono: scrivi la sigla, poi uno spazio o un segno, e diventa il testo intero ("cmq" →
// "comunque", ";firma" → "Cordiali saluti, Marta Rossi"). Confronto esatto, maiuscole comprese. Le sceglie chi usa
// l'app (Impostazioni › Suggerimenti): nessuna è attiva in partenza. Solo Foundation.

import Foundation

struct Abbreviation: Codable, Identifiable, Equatable {
    var id: UUID
    var trigger: String
    var expansion: String

    init(id: UUID = UUID(), trigger: String, expansion: String) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
    }

    /// Una sigla si può usare se non è vuota e non ha spazi; l'espansione se non è vuota.
    var isUsable: Bool {
        let t = trigger
        guard !t.isEmpty, !t.contains(where: { $0.isWhitespace || $0.isNewline }) else { return false }
        return !Abbreviations.clean(expansion).isEmpty
    }
}

enum Abbreviations {
    /// Le aperture che possono stare attaccate davanti alla sigla senza farne parte: "(cmq".
    private static let openers: Set<Character> = ["(", "[", "«", "“", "\"", "'"]

    /// L'espansione su una riga sola: niente a capo, niente spazi in coda.
    static func clean(_ expansion: String) -> String {
        let oneLine = expansion.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        return oneLine.trimmingCharacters(in: .whitespaces)
    }

    /// Dato il testo prima del cursore che finisce con il carattere di confine, la sigla da sostituire e la sua
    /// espansione. nil se l'ultima parola non è una sigla dell'elenco.
    static func match(before text: String, in list: [Abbreviation]) -> (trigger: String, expansion: String)? {
        guard !list.isEmpty, let boundary = text.last, !(boundary.isLetter || boundary.isNumber) else { return nil }
        // L'ultimo pezzo senza spazi prima del confine.
        let body = text.dropLast()
        var token = ""
        var index = body.endIndex
        while index > body.startIndex {
            let prev = body.index(before: index)
            let ch = body[prev]
            if ch.isWhitespace || ch.isNewline { break }
            token.insert(ch, at: token.startIndex)
            index = prev
        }
        guard !token.isEmpty else { return nil }
        if let found = find(token, in: list) { return found }
        // Senza le aperture attaccate davanti.
        let stripped = String(token.drop(while: { openers.contains($0) }))
        if !stripped.isEmpty, stripped != token, let found = find(stripped, in: list) { return found }
        return nil
    }

    private static func find(_ token: String, in list: [Abbreviation]) -> (trigger: String, expansion: String)? {
        for item in list where item.isUsable && item.trigger == token {
            return (item.trigger, clean(item.expansion))
        }
        return nil
    }
}

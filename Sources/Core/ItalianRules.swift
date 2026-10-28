// Correzioni italiane in linea, senza modello: scattano quando finisci una parola (spazio o punteggiatura).
// Solo parole che sbagliate non vogliono dire niente ("perche", "pò", "qual'è"): niente che sia ambiguo
// ("pero" è anche un albero, "sara" un nome, "si" un pronome). Il maiuscolo di partenza si conserva.
// Più la maiuscola dopo il punto, con una lista di abbreviazioni che non chiudono la frase.

import Foundation

enum ItalianRules {
    /// Parola sbagliata (minuscola) → parola giusta.
    static let words: [String: String] = [
        // accenti acuti e gravi
        "perche": "perché", "perchè": "perché", "poiche": "poiché", "poichè": "poiché",
        "affinche": "affinché", "affinchè": "affinché", "benche": "benché", "benchè": "benché",
        "finche": "finché", "finchè": "finché", "purche": "purché", "purchè": "purché",
        "nonche": "nonché", "nonchè": "nonché", "cioe": "cioè", "cioé": "cioè",
        "piu": "più", "gia": "già", "puo": "può", "cosi": "così", "percio": "perciò", "pero'": "però",
        "piu'": "più", "gia'": "già", "puo'": "può", "cosi'": "così", "percio'": "perciò",
        "e'": "è", "c'e": "c'è", "c'e'": "c'è", "sè": "sé", "nè": "né", "ne'": "né",
        "lunedi": "lunedì", "martedi": "martedì", "mercoledi": "mercoledì", "giovedi": "giovedì", "venerdi": "venerdì",
        "lunedi'": "lunedì", "martedi'": "martedì", "mercoledi'": "mercoledì", "giovedi'": "giovedì", "venerdi'": "venerdì",
        "citta": "città", "citta'": "città", "universita": "università", "universita'": "università",
        "liberta": "libertà", "liberta'": "libertà", "realta": "realtà", "realta'": "realtà",
        "attivita": "attività", "attivita'": "attività", "possibilita": "possibilità", "possibilita'": "possibilità",
        "qualita": "qualità", "qualita'": "qualità", "quantita": "quantità", "quantita'": "quantità",
        "novita": "novità", "novita'": "novità", "societa": "società", "societa'": "società",
        "comunita": "comunità", "comunita'": "comunità", "verita": "verità", "verita'": "verità",
        "difficolta": "difficoltà", "difficolta'": "difficoltà",
        "proprieta": "proprietà", "proprieta'": "proprietà", "velocita": "velocità", "velocita'": "velocità",
        "caffe": "caffè", "caffe'": "caffè", "the'": "tè",
        "pò": "po'",
        // apostrofi
        "qual'e": "qual è", "qual'è": "qual è", "qual'era": "qual era", "un'altro": "un altro", "un'amico": "un amico",
        "un'uomo": "un uomo", "un'anno": "un anno", "un'attimo": "un attimo", "un'esempio": "un esempio",
        "fà": "fa", "stà": "sta", "quì": "qui", "quà": "qua",
    ]

    /// Abbreviazioni dopo cui il punto non chiude la frase.
    static let abbreviations: Set<String> = [
        "es", "ecc", "etc", "dott", "dr", "sig", "sigg", "prof", "pag", "pagg", "art", "artt", "n", "nn", "tel", "cfr",
        "p", "pp", "vs", "avv", "ing", "geom", "rag", "ca", "ss", "a", "d", "v", "vol", "ed", "cap", "fig", "tab",
        "sez", "par", "rif", "all", "mr", "mrs", "ms", "st", "jr", "sr", "no", "inc", "ltd", "co",
    ]

    /// La versione giusta di `word`, oppure nil se non c'è niente da correggere.
    static func correction(for word: String) -> String? {
        guard !word.isEmpty else { return nil }
        // Tutto maiuscolo (almeno due lettere) è una sigla: si lascia stare. "E'" invece diventa "È".
        let letters = word.filter(\.isLetter)
        if letters.count > 1, letters == letters.uppercased() { return nil }
        let key = word.lowercased().replacingOccurrences(of: "’", with: "'")
        guard let fixed = words[key], fixed != key else { return nil }
        // Si conserva la maiuscola iniziale.
        if let first = word.first, first.isUppercase {
            return fixed.prefix(1).uppercased() + fixed.dropFirst()
        }
        return fixed
    }

    /// La parola appena finita, se dopo un punto che chiude una frase va in maiuscolo; nil altrimenti.
    /// `before` è il testo fino alla parola esclusa (quello che c'è prima di `word`).
    static func capitalized(_ word: String, before: String) -> String? {
        guard let first = word.first, first.isLowercase, word.count >= 2 else { return nil }
        guard word.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" }) else { return nil }
        guard let separator = before.last, separator == " " || separator == "\n" else { return nil }
        let result = word.prefix(1).uppercased() + word.dropFirst()
        // Il testo prima dello spazio o dell'a capo, senza spazi in coda.
        let head = String(before.dropLast()).replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression)
        if head.isEmpty { return nil }                      // la prima parola del campo: non si tocca (ricerche, indirizzi)
        if head.hasSuffix("\n") { return result }           // riga vuota prima: inizio di paragrafo
        guard let last = head.last, last == "." || last == "!" || last == "?" else { return nil }
        if last == ".", !head.hasSuffix("...") {
            // La parola prima del punto: un'abbreviazione, un'iniziale, un numero (elenco "3." o "1.2."), un indirizzo?
            let prev = String(head.dropLast()).split(whereSeparator: { $0.isWhitespace || $0.isNewline }).last.map(String.init) ?? ""
            let prevClean = prev.trimmingCharacters(in: .punctuationCharacters).lowercased()
            if abbreviations.contains(prevClean) { return nil }
            if prevClean.count == 1 { return nil }
            if prevClean.allSatisfy({ $0.isNumber || $0 == "." }) { return nil }
            if prev.contains(".") { return nil }
        }
        return result
    }

    /// La parola appena conclusa, dato il testo prima del cursore che finisce con il carattere di confine
    /// (spazio o punteggiatura). Restituisce la parola e il testo che la precede.
    static func lastWord(before text: String) -> (word: String, prefix: String)? {
        guard let boundary = text.last, !(boundary.isLetter || boundary.isNumber) else { return nil }
        let body = text.dropLast()
        var word = ""
        var index = body.endIndex
        while index > body.startIndex {
            let prev = body.index(before: index)
            let ch = body[prev]
            if ch.isLetter || ch.isNumber || ch == "'" || ch == "’" {
                word.insert(ch, at: word.startIndex)
                index = prev
            } else {
                break
            }
        }
        guard !word.isEmpty else { return nil }
        return (word, String(body[..<index]))
    }
}

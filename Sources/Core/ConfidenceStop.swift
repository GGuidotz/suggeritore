// La lunghezza del seguito decisa dal modello, non da un numero fisso di parole: si va avanti finché il modello è
// sicuro di quello che scrive e ci si ferma alla prima parola incerta (come fanno Cotypist e simili). Anche la prima
// parola deve superare una soglia: se il modello tira a indovinare già lì (un numero, una virgola a caso) non si
// suggerisce niente. Dalla seconda, ogni parola deve avere una probabilità minima, e anche l'insieme. Il tetto resta il
// numero massimo di parole scelto. Solo Foundation.

import Foundation

struct ConfidenceStop {
    let length: SuggestionLength
    let maxWords: Int
    /// Tutto il testo arrivato finora.
    private(set) var text = ""
    /// Il testo fin dove il modello era abbastanza sicuro (a confine di parola); vuoto finché non c'è una parola intera.
    private(set) var confident = ""
    /// Parole intere passate.
    private(set) var words = 0
    /// La prima parola era incerta: niente suggerimento.
    private(set) var rejected = false
    private var cumulative = 1.0
    private var wordProbability = 1.0

    init(length: SuggestionLength, maxWords: Int? = nil) {
        self.length = length
        self.maxWords = max(1, maxWords ?? length.maxWords)
    }

    /// La probabilità minima della prima parola (o del resto della parola in corso).
    static let firstWordFloor = 0.12

    /// La probabilità minima di una parola, dalla seconda in poi.
    var perWordFloor: Double {
        switch length {
        case .word: 1
        case .short: 0.25
        case .medium: 0.15
        case .long: 0.08
        }
    }

    /// La probabilità minima dell'insieme delle parole.
    var cumulativeFloor: Double {
        switch length {
        case .word: 1
        case .short: 0.02
        case .medium: 0.008
        case .long: 0.003
        }
    }

    /// Aggiunge un pezzo arrivato dal modello con la sua probabilità (nil se il motore non la dà). Vero quando conviene
    /// fermarsi: il seguito buono è `result`.
    mutating func add(_ piece: String, probability: Double?) -> Bool {
        let startsWord = piece.first.map { $0.isWhitespace || $0.isNewline } ?? false
        let hasWord = text.contains(where: { !$0.isWhitespace && !$0.isNewline })
        if startsWord, hasWord {
            // Una parola è finita: si tiene se il modello ne era sicuro.
            words += 1
            if words == 1, wordProbability < Self.firstWordFloor { rejected = true; return true }
            if words > 1, wordProbability < perWordFloor || cumulative < cumulativeFloor { return true }
            confident = text
            if words >= maxWords { return true }
            wordProbability = 1
        }
        text += piece
        if let p = probability {
            let clamped = Swift.min(1, Swift.max(p, 0.000_001))
            wordProbability *= clamped
            cumulative *= clamped
        }
        return false
    }

    /// Il seguito a risposta finita: `natural` se il modello si è fermato da solo (l'ultima parola è intera).
    /// Vuoto se già la prima parola era incerta.
    func result(natural: Bool) -> String {
        if rejected { return "" }
        if words == 0 {
            // Una parola sola, mai chiusa da uno spazio: vale la soglia della prima.
            return natural && wordProbability >= Self.firstWordFloor ? text : ""
        }
        if natural, wordProbability >= perWordFloor, cumulative >= cumulativeFloor { return text }
        return confident
    }
}

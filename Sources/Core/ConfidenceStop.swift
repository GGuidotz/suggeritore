// La lunghezza del seguito decisa dal modello, non da un numero fisso di parole: si va avanti finché il modello è
// sicuro di quello che scrive e ci si ferma alla prima parola incerta (come fanno Cotypist e simili). La prima parola
// si tiene sempre; dalla seconda, ogni parola deve avere una probabilità minima, e anche l'insieme. Il tetto resta
// `SuggestionLength.maxWords`. Solo Foundation.

import Foundation

struct ConfidenceStop {
    let length: SuggestionLength
    /// Tutto il testo arrivato finora.
    private(set) var text = ""
    /// Il testo fin dove il modello era abbastanza sicuro (a confine di parola); vuoto finché non c'è una parola intera.
    private(set) var confident = ""
    /// Parole intere passate.
    private(set) var words = 0
    private var cumulative = 1.0
    private var wordProbability = 1.0

    init(length: SuggestionLength) { self.length = length }

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
    /// fermarsi: il seguito buono è `confident`.
    mutating func add(_ piece: String, probability: Double?) -> Bool {
        let startsWord = piece.first.map { $0.isWhitespace || $0.isNewline } ?? false
        let hasWord = text.contains(where: { !$0.isWhitespace && !$0.isNewline })
        if startsWord, hasWord {
            // Una parola è finita: si tiene se il modello ne era sicuro.
            words += 1
            if words > 1, wordProbability < perWordFloor || cumulative < cumulativeFloor { return true }
            confident = text
            if words >= length.maxWords { return true }
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
    func result(natural: Bool) -> String {
        if natural {
            let lastOK = words == 0 || (wordProbability >= perWordFloor && cumulative >= cumulativeFloor)
            if lastOK || confident.isEmpty { return text }
        }
        return confident.isEmpty ? text : confident
    }
}

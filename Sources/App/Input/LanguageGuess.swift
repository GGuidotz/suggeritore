// La lingua del testo che stai scrivendo, dal riconoscitore di macOS: serve a dire al modello in che lingua continuare.

import NaturalLanguage

enum LanguageGuess {
    static func code(for text: String) -> String? {
        let sample = String(text.suffix(400))
        guard sample.count >= 12 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let language = recognizer.dominantLanguage else { return nil }
        let confidence = recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0
        return confidence >= 0.5 ? language.rawValue : nil
    }
}

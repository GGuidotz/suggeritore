// Cosa si dice al modello e come si pulisce quello che risponde. Le istruzioni sono in inglese perché i modelli
// piccoli le seguono meglio; il testo da continuare resta nella sua lingua e il modello deve rispondere in quella.
// Il modello di Apple ha una finestra piccola (circa 4.000 token): il contesto si tiene corto (TextContext.maxBefore).

import Foundation

enum Prompting {
    // MARK: - Completamento

    static func completionInstructions(_ r: CompletionRequest) -> String {
        var lines = [
            "You are an autocomplete engine inside a text field. The user is typing; you write ONLY the text that should come next, exactly where the cursor is.",
            "Rules:",
            "- Output only the continuation. No quotes, no explanations, no labels, no markdown, no emoji.",
            "- Never repeat text that is already before the cursor.",
            "- Write in the same language as the text (\(languageName(r.language))). Match its tone, register and formatting.",
            "- Keep it \(lengthHint(r.length)). Stop at the end of the sentence; do not start a new paragraph.",
            "- If the text before the cursor ends in the middle of a word, first complete that word, then continue.",
            "- If it ends with a space, start directly with the next word. If it ends with a letter or punctuation and the word is complete, start with a space.",
            "- If nothing sensible can follow, output an empty string.",
        ]
        if !r.context.after.isEmpty {
            lines.append("- There is text after the cursor on the same line; your continuation must join it smoothly and must not repeat it.")
        }
        if r.clipboard != nil {
            lines.append("- The clipboard content is given as context; use it only if it clearly helps (names, numbers, addresses).")
        }
        let own = r.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !own.isEmpty {
            lines.append("User preferences: \(own)")
        }
        return lines.joined(separator: "\n")
    }

    static func completionPrompt(_ r: CompletionRequest) -> String {
        var out = "App: \(r.context.appName.isEmpty ? "unknown" : r.context.appName)\n"
        if let clip = r.clipboard, !clip.isEmpty {
            out += "Clipboard:\n«\(String(clip.prefix(500)))»\n"
        }
        out += "Text before the cursor:\n«\(r.context.before)»\n"
        if !r.context.after.isEmpty {
            out += "Text after the cursor on the same line:\n«\(r.context.after)»\n"
        }
        if r.context.before.last?.isWhitespace == true {
            out += "The text ends with a space. Continue with the next word."
        } else if r.context.partialWord.isEmpty {
            out += "The text ends right after a complete word or punctuation. Start with a space."
        } else {
            out += "The text ends in the middle of the word \"\(r.context.partialWord)\". Complete it, then continue."
        }
        return out
    }

    /// Dalla risposta grezza al seguito da mostrare: via virgolette, ripetizioni, emoji e a capo; taglio a fine frase e
    /// al numero di parole scelto; spazio iniziale giusto. nil se non resta niente di utile.
    static func cleanCompletion(_ raw: String, for r: CompletionRequest) -> String? {
        var text = raw
        text = text.replacingOccurrences(of: "```", with: "")
        text = TextTokens.removingEmoji(text)
        // Il modello a volte etichetta la risposta.
        for label in ["Continuation:", "Completion:", "Output:", "Text:"] where text.trimmingCharacters(in: .whitespaces).hasPrefix(label) {
            text = String(text.trimmingCharacters(in: .whitespaces).dropFirst(label.count))
        }
        // Virgolette intorno a tutto.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in [("«", "»"), ("\"", "\""), ("“", "”"), ("'", "'")] where trimmed.hasPrefix(open) && trimmed.hasSuffix(close) && trimmed.count > 2 {
            text = String(trimmed.dropFirst().dropLast())
        }
        // Un solo rigo: gli a capo diventano spazi, e si prende al massimo il numero di frasi scelto.
        text = text.replacingOccurrences(of: "\r", with: "")
        if let newline = text.firstIndex(of: "\n") {
            let firstLine = text[..<newline].trimmingCharacters(in: .whitespaces)
            text = firstLine.isEmpty ? String(text[text.index(after: newline)...]).components(separatedBy: "\n").first ?? "" : String(firstLine)
        }
        text = collapseSpaces(text)

        // Se ripete la fine del testo già scritto, via la parte ripetuta.
        text = removingOverlap(text, before: r.context.before)
        // Se finisce ripetendo l'inizio del testo che segue, via anche quello.
        if !r.context.after.isEmpty { text = removingTrailingOverlap(text, after: r.context.after) }

        // Spazio iniziale: giusto rispetto a ciò che precede.
        let before = r.context.before
        if before.last?.isWhitespace == true || before.isEmpty {
            text = String(text.drop(while: { $0 == " " }))
        } else if r.context.partialWord.isEmpty, let first = text.first, first.isLetter || first.isNumber {
            text = " " + text
        }
        // Mai due spazi tra prima e dopo.
        if before.last == " ", text.first == " " { text = String(text.dropFirst()) }

        // Taglio a fine frase e a numero di parole.
        text = cutToSentences(text, max: r.length.maxSentences)
        text = cutToWords(text, max: r.length.maxWords)
        text = text.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        // Il seguito deve legarsi bene a ciò che viene dopo sulla riga.
        if let next = r.context.after.first, !next.isWhitespace, !next.isPunctuation, text.last?.isLetter == true {
            text += " "
        }
        let meaningful = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !meaningful.isEmpty, meaningful != "\"\"" else { return nil }
        return text
    }

    // MARK: - Riscrittura

    static func rewriteInstructions(_ instruction: String, language: String?) -> String {
        """
        You rewrite text for the user. \(instruction)
        Rules: answer with the rewritten text only, in the same language as the original (\(languageName(language))). \
        No quotes, no preamble, no explanation, no markdown, no emoji. Keep line breaks and paragraphs where the original has them. \
        Never add information that is not in the original.
        """
    }

    static func rewritePrompt(_ text: String) -> String {
        "Original text:\n«\(text)»\n\nRewritten text:"
    }

    static func cleanRewrite(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "```", with: "")
        text = TextTokens.removingEmoji(text).trimmingCharacters(in: .whitespacesAndNewlines)
        for label in ["Rewritten text:", "Rewritten:", "Output:"] where text.hasPrefix(label) {
            text = String(text.dropFirst(label.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for (open, close) in [("«", "»"), ("\"", "\""), ("“", "”")] where text.hasPrefix(open) && text.hasSuffix(close) && text.count > 2 {
            text = String(text.dropFirst().dropLast())
        }
        return text
    }

    // MARK: - Pezzi

    static func languageName(_ code: String?) -> String {
        guard let code, !code.isEmpty else { return "the language of the text" }
        switch code {
        case "it": return "Italian"
        case "en": return "English"
        case "fr": return "French"
        case "de": return "German"
        case "es": return "Spanish"
        case "pt": return "Portuguese"
        default: return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "the language of the text"
        }
    }

    private static func lengthHint(_ length: SuggestionLength) -> String {
        switch length {
        case .short: "very short: a few words, at most \(length.maxWords)"
        case .medium: "short: one sentence, at most \(length.maxWords) words"
        case .long: "at most two sentences, at most \(length.maxWords) words"
        }
    }

    static func collapseSpaces(_ text: String) -> String {
        text.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
    }

    /// "…come stai" + risposta "come stai oggi?" → " oggi?": via la parte che ripete la coda del testo scritto.
    static func removingOverlap(_ completion: String, before: String) -> String {
        let tail = String(before.suffix(120)).lowercased()
        let comp = completion.lowercased()
        let compLeading = comp.drop(while: { $0 == " " })
        let leading = comp.count - compLeading.count
        // Il più lungo suffisso di `tail` che è prefisso della risposta (senza gli spazi iniziali), a confine di parola.
        var best = 0
        let tailChars = Array(tail), compChars = Array(compLeading)
        let maxLen = min(tailChars.count, compChars.count)
        if maxLen > 0 {
            for len in stride(from: maxLen, through: 3, by: -1) {
                if Array(tailChars.suffix(len)) == Array(compChars.prefix(len)) {
                    let startsAtBoundary = len == tailChars.count || !(tailChars[tailChars.count - len - 1].isLetter)
                    let endsAtBoundary = len == compChars.count || !(compChars[len].isLetter)
                    if startsAtBoundary && endsAtBoundary { best = len; break }
                }
            }
        }
        guard best > 0 else { return completion }
        return String(completion.dropFirst(leading + best))
    }

    static func removingTrailingOverlap(_ completion: String, after: String) -> String {
        let head = String(after.prefix(80)).lowercased().trimmingCharacters(in: .whitespaces)
        let comp = completion.lowercased()
        guard !head.isEmpty else { return completion }
        let compChars = Array(comp), headChars = Array(head)
        for len in stride(from: min(compChars.count, headChars.count), through: 3, by: -1) {
            if Array(compChars.suffix(len)) == Array(headChars.prefix(len)) {
                return String(completion.dropLast(len)).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            }
        }
        return completion
    }

    /// Tiene al massimo `max` frasi: taglia dopo il punto, il punto interrogativo o esclamativo seguito da spazio.
    static func cutToSentences(_ text: String, max: Int) -> String {
        var count = 0
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            if ch == "." || ch == "!" || ch == "?" {
                var next = text.index(after: index)
                while next < text.endIndex, text[next] == "." || text[next] == "!" || text[next] == "?" || text[next] == "\"" || text[next] == "»" || text[next] == ")" {
                    next = text.index(after: next)
                }
                if next == text.endIndex || text[next].isWhitespace {
                    count += 1
                    if count >= max { return String(text[..<next]) }
                }
                index = next
            } else {
                index = text.index(after: index)
            }
        }
        return text
    }

    /// Tiene al massimo `max` parole, chiudendo dove possibile su una virgola o fine frase.
    static func cutToWords(_ text: String, max: Int) -> String {
        let words = TextTokens.words(withLeadingSpace: text)
        guard words.count > max else { return text }
        var kept = Array(words.prefix(max))
        // Meglio fermarsi su una virgola o un punto negli ultimi pezzi, se c'è.
        let closers: Set<Character> = [",", ".", ";", ":", "!", "?"]
        if let i = kept.lastIndex(where: { word in word.last.map { closers.contains($0) } == true }), i >= max / 2 {
            kept = Array(kept.prefix(i + 1))
        }
        return kept.joined()
    }
}

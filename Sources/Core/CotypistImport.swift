// Quello che si può riusare di Cotypist, se è installato: le statistiche (completionStats.json, solo conteggi per
// giorno, niente testo) e i modelli GGUF già scaricati nella sua cartella. Le sue memorie (cotypist.db) sono cifrate e
// non si leggono: non ci proviamo. Solo Foundation.

import Foundation

enum CotypistImport {
    struct Stats: Equatable {
        var words: Int
        var completions: Int
        var days: Int
    }

    /// La cartella di Cotypist in Application Support, se c'è.
    static var supportDirectory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let url = base.appendingPathComponent("app.cotypist.Cotypist", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static var isInstalled: Bool { supportDirectory != nil }

    /// Le parole e i completamenti accettati in Cotypist, sommati su tutti i giorni; nil se il file manca o non si legge.
    static func readStats() -> Stats? {
        guard let directory = supportDirectory else { return nil }
        let url = directory.appendingPathComponent("completionStats.json")
        guard let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let perDay = root["perDay"] as? [String: Any] else { return nil }
        var words = 0, completions = 0, days = 0
        for (_, dayValue) in perDay {
            guard let day = dayValue as? [String: Any] else { continue }
            var dayWords = 0
            for (_, kindValue) in day {
                guard let kind = kindValue as? [String: Any] else { continue }
                dayWords += (kind["wordCountTotal"] as? NSNumber)?.intValue ?? 0
                completions += (kind["completionCount"] as? NSNumber)?.intValue ?? 0
            }
            words += dayWords
            if dayWords > 0 { days += 1 }
        }
        guard words > 0 || completions > 0 else { return nil }
        return Stats(words: words, completions: completions, days: days)
    }

    /// I file GGUF nella cartella Models di Cotypist (il suo Gemma 3 1B base, circa 850 MB).
    static func modelFiles() -> [URL] {
        guard let directory = supportDirectory else { return [] }
        let models = directory.appendingPathComponent("Models", isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: models.path) else { return [] }
        return names.filter { $0.lowercased().hasSuffix(".gguf") }.sorted().map { models.appendingPathComponent($0) }
    }
}

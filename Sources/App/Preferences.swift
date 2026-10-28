// Le scelte di chi usa l'app, salvate in UserDefaults. Predefiniti sensati: si usa senza toccare nulla.

import Foundation

enum EngineChoice: String, CaseIterable, Codable, Identifiable {
    case apple, rulesOnly
    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: "Apple Intelligence"
        case .rulesOnly: L("Solo regole e memoria")
        }
    }
}

@MainActor
final class Preferences: ObservableObject {
    private let defaults = UserDefaults.standard

    /// Suggerimenti accesi (il menu nella barra li mette in pausa).
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled") } }
    @Published var engine: EngineChoice { didSet { save(engine, "engine") } }
    @Published var length: SuggestionLength { didSet { save(length, "length") } }
    /// Secondi di pausa prima di chiedere un suggerimento.
    @Published var delay: Double { didSet { defaults.set(delay, forKey: "delay") } }
    @Published var acceptWord: KeyBinding { didSet { save(acceptWord, "acceptWord") } }
    @Published var acceptAll: KeyBinding { didSet { save(acceptAll, "acceptAll") } }
    @Published var dismiss: KeyBinding { didSet { save(dismiss, "dismiss") } }
    @Published var rewrite: KeyBinding { didSet { save(rewrite, "rewrite") } }
    /// Completamento a metà riga (sperimentale).
    @Published var midLine: Bool { didSet { defaults.set(midLine, forKey: "midLine") } }
    @Published var italianCorrections: Bool { didSet { defaults.set(italianCorrections, forKey: "italianCorrections") } }
    @Published var capitalizeSentences: Bool { didSet { defaults.set(capitalizeSentences, forKey: "capitalizeSentences") } }
    @Published var phraseMemory: Bool { didSet { defaults.set(phraseMemory, forKey: "phraseMemory") } }
    /// Gli appunti come contesto per il modello: lo si sceglie nella guida al primo avvio.
    @Published var clipboardContext: Bool { didSet { defaults.set(clipboardContext, forKey: "clipboardContext") } }
    @Published var clipboardDecided: Bool { didSet { defaults.set(clipboardDecided, forKey: "clipboardDecided") } }
    /// Bundle id delle app dove non suggerire mai.
    @Published var excludedApps: Set<String> { didSet { save(Array(excludedApps).sorted(), "excludedApps") } }
    /// Una frase di istruzioni per il modello (tono, stile).
    @Published var instructions: String { didSet { defaults.set(instructions, forKey: "instructions") } }
    /// Parole accettate da sempre: un numero che fa piacere vedere.
    @Published var acceptedWordsTotal: Int { didSet { defaults.set(acceptedWordsTotal, forKey: "acceptedWordsTotal") } }
    /// La guida dei primi passi è già stata vista.
    @Published var onboardingDone: Bool { didSet { defaults.set(onboardingDone, forKey: "onboardingDone") } }
    @Published var language: AppLanguage {
        didSet { Localization.language = language; save(language, "language") }
    }
    @Published var autoCheckUpdates: Bool { didSet { defaults.set(autoCheckUpdates, forKey: "autoCheckUpdates") } }

    init() {
        func load<T: Decodable>(_ key: String, _ fallback: T) -> T {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
            return value
        }
        let d = UserDefaults.standard
        enabled = d.object(forKey: "enabled") as? Bool ?? true
        engine = load("engine", EngineChoice.apple)
        length = load("length", SuggestionLength.medium)
        delay = d.object(forKey: "delay") as? Double ?? 0.35
        acceptWord = load("acceptWord", KeyBinding.tab)
        acceptAll = load("acceptAll", KeyBinding.shiftTab)
        dismiss = load("dismiss", KeyBinding.escape)
        rewrite = load("rewrite", KeyBinding.controlOptionR)
        midLine = d.bool(forKey: "midLine")
        italianCorrections = d.object(forKey: "italianCorrections") as? Bool ?? true
        capitalizeSentences = d.object(forKey: "capitalizeSentences") as? Bool ?? true
        phraseMemory = d.object(forKey: "phraseMemory") as? Bool ?? true
        clipboardContext = d.bool(forKey: "clipboardContext")
        clipboardDecided = d.bool(forKey: "clipboardDecided")
        excludedApps = Set(load("excludedApps", Exclusions.defaults))
        instructions = d.string(forKey: "instructions") ?? ""
        acceptedWordsTotal = d.integer(forKey: "acceptedWordsTotal")
        onboardingDone = d.bool(forKey: "onboardingDone")
        language = load("language", AppLanguage.system)
        autoCheckUpdates = d.object(forKey: "autoCheckUpdates") as? Bool ?? true
        Localization.language = language
    }

    func isExcluded(_ bundleID: String) -> Bool { excludedApps.contains(bundleID) }

    func setExcluded(_ bundleID: String, _ excluded: Bool) {
        if excluded { excludedApps.insert(bundleID) } else { excludedApps.remove(bundleID) }
    }

    func resetExclusions() { excludedApps = Set(Exclusions.defaults) }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}

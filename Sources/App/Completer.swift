// Il cuore dell'app: ascolta i tasti, aspetta che ti fermi, legge il campo, chiede un seguito (prima alla memoria e
// alle regole, poi al modello) e lo mostra in grigio, già mentre il modello lo scrive. Tab accetta una parola,
// Maiusc-Tab tutto, Esc scarta; se scrivi proprio quello che era suggerito il suggerimento avanza, se scrivi altro
// sparisce. A fine parola espande le abbreviazioni e applica le correzioni italiane. Il motore lo sceglie
// activeEngine(): Gemma se c'è (e intanto che si avvia Apple Intelligence), Apple Intelligence, o solo regole.
// Tutto sul main actor; il modello lavora in un Task che si annulla appena riprendi a scrivere.

import AppKit
import Combine

@MainActor
final class Completer: ObservableObject {
    enum Status: Equatable {
        case off, noPermission, secureInput, excluded(String), ready, thinking, suggesting

        /// Una frase per il menu e le impostazioni.
        var title: String {
            switch self {
            case .off: L("In pausa")
            case .noPermission: L("Serve il permesso Accessibilità")
            case .secureInput: L("Input sicuro attivo: niente suggerimenti")
            case .excluded(let app): L("Escluso in %@", app)
            case .ready: L("Pronto")
            case .thinking: L("Sto pensando…")
            case .suggesting: L("Suggerimento in corso")
            }
        }
    }

    struct Stats {
        var shown = 0, acceptedWords = 0, acceptedAll = 0, dismissed = 0, memoryHits = 0, corrections = 0, modelFailures = 0
        /// Suggerimenti di cui hai preso almeno una parola, e abbreviazioni espanse.
        var acceptedSuggestions = 0, expansions = 0
    }

    @Published private(set) var status: Status = .off
    @Published private(set) var frontApp: (bundleID: String, name: String)?
    @Published private(set) var stats = Stats()
    @Published private(set) var lastError: String?
    /// Quanto ha messo il modello a rispondere, in secondi, nelle ultime 20 richieste.
    @Published private(set) var responseTimes: [Double] = []

    /// I tempi di una richiesta al modello, per la diagnostica: solo numeri.
    struct Latency {
        /// Lettura del campo con l'Accessibilità, in millisecondi.
        var readMs: Double
        /// Dalla richiesta al primo testo grigio sullo schermo; nil se non è comparso prima della fine.
        var firstMs: Double?
        /// Dalla richiesta alla risposta completa.
        var totalMs: Double
        /// Token di prompt elaborati e ripresi dalla cache, se il motore li dà (llama-server).
        var timings: LlamaTimings?
    }
    /// Le ultime 30 richieste andate a buon fine.
    private(set) var latencies: [Latency] = []

    let prefs: Preferences
    let apple = AppleEngine()
    let llama: LlamaServer
    let memory = PhraseMemory()
    let monitor = KeyMonitor()
    let overlay = GhostOverlay()
    private lazy var rules = RulesEngine(memory: memory)
    private let usageReader = OwnUsageReader()

    /// Chiamato dalla scorciatoia "Riscrivi la selezione".
    var onRewriteRequested: (() -> Void)?
    /// Vero mentre il pannello "Riscrivi" è aperto: nei nostri campi non si suggerisce.
    var ignoreOwnProcess = false

    private var field: FocusedField?
    private var context: TextContext?
    private var suggestion: Suggestion?
    /// Il testo prima del cursore quando il suggerimento è nato, e quanto ne è stato accettato: per la memoria.
    private var origin = ""
    private var acceptedSoFar = ""
    /// Del suggerimento sullo schermo hai già preso qualcosa (per contare i suggerimenti accettati una volta sola).
    private var acceptedCurrent = false
    private var debounceTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    private var generation = 0
    /// Il suggerimento sullo schermo è ancora a metà: il modello lo sta scrivendo.
    private var streaming = false
    /// Il suggerimento sullo schermo è rimasto a metà (l'hai preso prima che il modello finisse): non si impara.
    private var cutShort = false
    /// Dove sta il testo fantasma: mentre arrivano i pezzi il cursore non si muove, non serve rileggerlo.
    private var ghostCaret: CGRect?
    private var ghostFont: NSFont?
    private var lastPartialAt = Date.distantPast
    /// Quando è partita la richiesta in corso e quando è comparso il suo primo pezzo.
    private var requestStartedAt = Date.distantPast
    private var firstPieceMs: Double?
    private var bag = Set<AnyCancellable>()

    init(prefs: Preferences) {
        self.prefs = prefs
        llama = LlamaServer(prefs: prefs)
    }

    var ownUsage: ProcessUsage? { usageReader.read() }

    // MARK: - Avvio

    func start() {
        monitor.onKeyDown = { [unowned self] stroke in self.handle(stroke) }
        monitor.onMouseDown = { [unowned self] in self.dismiss(reason: nil) }
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.appChanged() }
            .store(in: &bag)
        prefs.objectWillChange.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatus() }
            .store(in: &bag)
        // Chi guarda il Completer (menu, impostazioni) vede anche lo stato del server di Gemma.
        llama.objectWillChange.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
        // Un altro motore scelto: il server di Gemma non serve più.
        prefs.$engine.dropFirst().removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.engineChoiceChanged() }
            .store(in: &bag)
        // Il modello pronto prima che serva: all'avvio, al risveglio del Mac e quando lo chiedi nelle impostazioni.
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.preloadModel() }
            .store(in: &bag)
        prefs.$keepModelLoaded.dropFirst().removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] on in if on { self?.preloadModel() } }
            .store(in: &bag)
        startMonitorIfPossible()
        appChanged()
        if prefs.useOllama { llama.refreshOllama() }
        preloadModel()
        if preferredKind == .apple { apple.prewarm() }
        diag(.app, "completer started, tap \(monitor.isRunning ? "on" : "off")")
    }

    /// Avvia Gemma in anticipo se deve restare pronto (e se è il motore scelto).
    private func preloadModel() {
        guard prefs.enabled, prefs.keepModelLoaded, preferredKind == .gemma, !llama.shouldSaveEnergy else { return }
        if llama.state == .stopped { llama.start() }
    }

    private func engineChoiceChanged() {
        preloadModel()
        if preferredKind != .gemma, llama.state != .stopped { llama.stop() }
        if preferredKind == .apple { apple.prewarm() }
    }

    // MARK: - Motore

    /// Il motore che la preferenza chiede adesso, senza avviare niente. nil: solo regole e memoria.
    var preferredKind: EngineKind? {
        switch prefs.engine {
        case .rulesOnly: return nil
        case .apple: return .apple
        case .gemma: return .gemma
        case .auto:
            if llama.isAvailable { return .gemma }
            return apple.unavailableReason == nil ? .apple : nil
        }
    }

    /// Il motore da usare per una richiesta. Con Gemma conta come uso del server (e lo avvia se è fermo); finché
    /// non è pronto risponde Apple Intelligence, se c'è, senza aspettare. nil: solo regole e memoria.
    func activeEngine(forRewrite: Bool = false) -> (any CompletionEngine)? {
        guard let kind = preferredKind else { return nil }
        if kind == .gemma {
            llama.noteUse()
            // Un modello base continua il testo ma non segue istruzioni: per riscrivere si passa ad Apple Intelligence.
            if let engine = llama.engine, !(forRewrite && engine.rawCompletion) { return engine }
        }
        if apple.unavailableReason == nil { return apple }
        return nil
    }

    /// Il nome del motore che risponderebbe adesso (senza avviare niente), nil se nessuno.
    var currentEngineName: String? {
        guard let kind = preferredKind else { return nil }
        if kind == .gemma {
            if let engine = llama.engine { return engine.displayName }
            if llama.state == .stopped { return llama.modelTitle }   // si avvia alla prima richiesta
        }
        return apple.unavailableReason == nil ? apple.displayName : nil
    }

    /// Una frase su Gemma quando non è ancora pronto, per il menu; nil se non c'è niente da dire.
    var engineNotice: String? {
        guard preferredKind == .gemma else { return nil }
        switch llama.state {
        case .starting: return L("Gemma: si avvia…")
        case .downloading: return L("Gemma: sto scaricando il modello…")
        case .failed: return L("Gemma non è disponibile: vedi Impostazioni › Motori.")
        case .stopped, .ready: return nil
        }
    }

    /// La riga di stato del menu: "Pronto · Gemma 3 1B".
    var statusLine: String {
        switch status {
        case .ready, .thinking, .suggesting:
            return status.title + " · " + (currentEngineName ?? L("Solo regole e memoria"))
        default:
            return status.title
        }
    }

    /// Il tempo medio di risposta del modello nelle ultime 20 richieste, in millisecondi.
    var averageResponseMs: Int? {
        guard !responseTimes.isEmpty else { return nil }
        let total = responseTimes.reduce(0, +)
        return Int((total / Double(responseTimes.count) * 1000).rounded())
    }

    private func recordResponseTime(_ seconds: TimeInterval) {
        responseTimes.append(seconds)
        if responseTimes.count > 20 { responseTimes.removeFirst(responseTimes.count - 20) }
    }

    private func recordLatency(_ latency: Latency) {
        latencies.append(latency)
        if latencies.count > 30 { latencies.removeFirst(latencies.count - 30) }
    }

    /// Le mediane delle ultime richieste, in inglese, per il report: "read 12 ms, first 180 ms, …". nil se non ce ne sono.
    var latencySummary: String? {
        guard !latencies.isEmpty else { return nil }
        func median(_ values: [Double]) -> Int? {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted()
            return Int(sorted[sorted.count / 2].rounded())
        }
        var parts: [String] = []
        if let read = median(latencies.map(\.readMs)) { parts.append("read \(read) ms") }
        if let first = median(latencies.compactMap(\.firstMs)) { parts.append("first text \(first) ms") }
        if let total = median(latencies.map(\.totalMs)) { parts.append("complete \(total) ms") }
        let timings = latencies.compactMap(\.timings)
        if let prompt = median(timings.map { Double($0.promptTokens) }),
           let promptMs = median(timings.map(\.promptMs)) {
            parts.append("prompt \(prompt) tokens in \(promptMs) ms")
        }
        if let cached = median(timings.compactMap { $0.cachedTokens.map(Double.init) }) {
            parts.append("from cache \(cached) tokens")
        }
        let speeds = timings.filter { $0.predictedMs > 0 }.map { Double($0.predictedTokens) / $0.predictedMs * 1000 }
        if let speed = median(speeds) { parts.append("\(speed) tokens/s") }
        return parts.joined(separator: ", ") + " (median of \(latencies.count))"
    }

    /// I dati per la vista compatta (Sources/Island): stato, motore, conteggi.
    var statusInfo: TypeWithMeStatusInfo {
        var tone: TypeWithMeStatusInfo.Tone
        switch status {
        case .ready: tone = .ok
        case .thinking, .suggesting: tone = .busy
        case .off, .excluded: tone = .off
        case .noPermission, .secureInput: tone = .warning
        }
        if tone == .ok, llama.state.isBusy, preferredKind == .gemma { tone = .busy }
        return TypeWithMeStatusInfo(statusText: status.title,
                                     tone: tone,
                                     engineName: currentEngineName ?? L("Solo regole e memoria"),
                                     engineDetail: engineNotice,
                                     wordsToday: prefs.acceptedToday,
                                     wordsTotal: prefs.acceptedWordsTotal,
                                     shownThisSession: stats.shown,
                                     acceptedThisSession: stats.acceptedSuggestions,
                                     averageResponseMs: averageResponseMs)
    }

    /// Prova ad accendere il tap sulla tastiera: serve il permesso Accessibilità.
    @discardableResult
    func startMonitorIfPossible() -> Bool {
        if monitor.isRunning { refreshStatus(); return true }
        guard Permissions.accessibility else { refreshStatus(); return false }
        let ok = monitor.start()
        diag(.permissions, ok ? "key tap started" : "key tap refused")
        refreshStatus()
        return ok
    }

    func refreshStatus() {
        let new: Status
        if !prefs.enabled { new = .off }
        else if !monitor.isRunning { new = .noPermission }
        else if KeyMonitor.secureInputActive { new = .secureInput }
        else if let app = frontApp, prefs.isExcluded(app.bundleID) { new = .excluded(app.name) }
        else if suggestion != nil { new = .suggesting }
        else if requestTask != nil { new = .thinking }
        else { new = .ready }
        if new != status { status = new }
    }

    private func appChanged() {
        frontApp = FocusReader.frontmostApp()
        dismiss(reason: nil)
    }

    // MARK: - Tasti

    private func handle(_ s: KeyStroke) -> KeyDecision {
        guard prefs.enabled, monitor.isRunning else { return .pass }
        if prefs.rewrite.matches(keyCode: s.keyCode, flags: s.flags) {
            dismiss(reason: nil)
            onRewriteRequested?()
            return .swallow
        }
        if KeyMonitor.secureInputActive {
            dismiss(reason: nil)
            return .pass
        }
        if let suggestion {
            let accept = prefs.acceptWord.matches(keyCode: s.keyCode, flags: s.flags)
            let acceptEverything = prefs.acceptAll.matches(keyCode: s.keyCode, flags: s.flags)
            if accept || acceptEverything {
                // Il fuoco è ancora nello stesso campo? Altrimenti il tasto va all'app e il suggerimento sparisce.
                guard let field, let now = FocusReader.focusedField(), CFEqual(now.element, field.element) else {
                    dismiss(reason: nil)
                    return .pass
                }
                // Prendi quello che c'è: se il modello stava ancora scrivendo, si ferma qui.
                stopStreaming()
                if accept { acceptWord() } else { acceptAll() }
                return .swallow
            }
            if prefs.dismiss.matches(keyCode: s.keyCode, flags: s.flags) {
                stats.dismissed += 1
                dismiss(reason: "dismissed")
                return .swallow
            }
            if s.isPrintable, !s.characters.isEmpty, suggestion.text.hasPrefix(s.characters) {
                // Stai scrivendo proprio quello che era suggerito: il suggerimento avanza.
                stopStreaming()
                acceptedSoFar += s.characters
                let rest = String(suggestion.text.dropFirst(s.characters.count))
                if rest.trimmingCharacters(in: .whitespaces).isEmpty {
                    finishSuggestion(learn: true)
                    scheduleSuggestion()
                } else {
                    self.suggestion = Suggestion(text: rest, source: suggestion.source)
                    reposition()
                }
                return .pass
            }
            dismiss(reason: nil)
        }
        guard !s.hasCommandOrControl else { return .pass }
        if s.isPrintable {
            let wantsFix = prefs.italianCorrections || !prefs.abbreviations.isEmpty
            if wantsFix, Self.isBoundary(s.characters) { scheduleBoundaryFix(boundary: s.characters) }
            scheduleSuggestion()
        } else if s.isBackspace {
            scheduleSuggestion()
        }
        return .pass
    }

    private static func isBoundary(_ characters: String) -> Bool {
        guard let c = characters.first, characters.count == 1 else { return false }
        return " \t.,;:!?)»\"".contains(c)
    }

    // MARK: - Suggerire

    /// Chiede un seguito dopo la pausa scelta, o dopo `delay` secondi (subito dopo un'accettazione: la cache del
    /// prompt è calda e il testo nuovo è già nel campo).
    private func scheduleSuggestion(delay override: Double? = nil) {
        debounceTask?.cancel()
        requestTask?.cancel()
        requestTask = nil
        generation += 1
        let delay = override ?? prefs.delay
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.produceSuggestion()
        }
    }

    private func produceSuggestion() {
        guard prefs.enabled, monitor.isRunning, !KeyMonitor.secureInputActive else { return }
        let readBegan = Date()
        guard let field = FocusReader.focusedField(), !field.isSecure, field.selection.length == 0 else { return }
        guard !prefs.isExcluded(field.bundleID) else { return }
        if ignoreOwnProcess, field.pid == getpid() { return }
        guard let before = FocusReader.text(before: field, max: TextContext.maxBefore) else { return }
        guard before.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 else { return }
        var after = ""
        if prefs.midLine {
            after = FocusReader.text(after: field, max: TextContext.maxAfter) ?? ""
        } else if let next = FocusReader.text(after: field, max: 2), !next.trimmingCharacters(in: .whitespaces).isEmpty {
            return   // c'è testo dopo il cursore e il completamento a metà riga è spento
        }
        let context = TextContext(before: before, after: after, appName: field.appName, bundleID: field.bundleID)
        guard context.endsAtWordBoundary || context.partialWord.count >= 3 else { return }
        self.field = field
        self.context = context
        generation += 1
        let gen = generation

        if let instant = rules.suggestion(for: context, useMemory: prefs.phraseMemory) {
            stats.memoryHits += 1
            show(instant, field: field, context: context)
            return
        }
        guard let engine = activeEngine() else { refreshStatus(); return }
        // Gemma: inizio del testo ancorato, così llama.cpp riusa il prompt già elaborato (Models.swift, anchored).
        let limited = engine.kind == .gemma ? context.anchored(caret: field.caret, max: engine.contextLimit)
                                            : context.limited(to: engine.contextLimit)
        let request = CompletionRequest(context: limited, length: prefs.length,
                                        language: LanguageGuess.code(for: before), instructions: prefs.instructions,
                                        appInstructions: prefs.instruction(forApp: field.bundleID),
                                        clipboard: clipboardIfAllowed())
        let source: SuggestionSource = engine.kind == .gemma ? .gemma : .apple
        let started = Date()
        let readMs = started.timeIntervalSince(readBegan) * 1000
        requestStartedAt = started
        firstPieceMs = nil
        // I pezzi arrivano da un thread qualunque: si torna sul main actor, in ordine.
        let partial: @Sendable (String) -> Void = { [weak self] text in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.showPartial(text, request: request, generation: gen, source: source) }
            }
        }
        requestTask = Task { [weak self] in
            let result: Result<String, Error>
            do { result = .success(try await engine.complete(request, partial: partial)) } catch { result = .failure(error) }
            guard !Task.isCancelled, let self, self.generation == gen else { return }
            self.requestTask = nil
            switch result {
            case .success(let raw):
                let elapsed = Date().timeIntervalSince(started)
                self.recordResponseTime(elapsed)
                self.recordLatency(Latency(readMs: readMs, firstMs: self.firstPieceMs ?? elapsed * 1000, totalMs: elapsed * 1000,
                                           timings: (engine as? LlamaEngine)?.lastTimings))
                self.finishStream(raw, request: request, field: field, context: context, source: source)
            case .failure(let error):
                self.stats.modelFailures += 1
                self.lastError = error.localizedDescription
                diag(.engine, "\(engine.kind.rawValue) failed: \(error.localizedDescription)")
                self.clearPartial()
                self.refreshStatus()
            }
        }
        refreshStatus()
    }

    /// Un pezzo del seguito mentre il modello scrive: il primo appare (se il cursore è ancora lì), i successivi
    /// aggiornano il testo fantasma nello stesso punto. Niente taglio a fine frase finché non è finito.
    private func showPartial(_ raw: String, request: CompletionRequest, generation gen: Int, source: SuggestionSource) {
        guard generation == gen, requestTask != nil, let field, let context else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPartialAt) >= 0.04 else { return }   // al più un aggiornamento ogni 40 ms
        guard let cleaned = Prompting.cleanCompletion(raw, for: request, final: false) else { return }
        if streaming, let current = suggestion {
            guard cleaned != current.text else { return }
            lastPartialAt = now
            suggestion = Suggestion(text: cleaned, source: source)
            overlay.show(cleaned, font: ghostFont, caret: ghostCaret, fieldFrame: field.frame)
            return
        }
        guard suggestion == nil else { return }
        // Il primo pezzo: il cursore è ancora lì?
        guard let current = FocusReader.focusedField(), CFEqual(current.element, field.element), current.caret == field.caret
        else { return }
        lastPartialAt = now
        show(Suggestion(text: cleaned, source: source), field: current, context: context)
        streaming = true
        firstPieceMs = now.timeIntervalSince(requestStartedAt) * 1000
    }

    /// La risposta intera: pulizia completa. Se il seguito era già sullo schermo si aggiorna lì, altrimenti appare ora.
    private func finishStream(_ raw: String, request: CompletionRequest, field: FocusedField, context: TextContext,
                              source: SuggestionSource) {
        let wasStreaming = streaming && suggestion != nil
        streaming = false
        guard let cleaned = Prompting.cleanCompletion(raw, for: request) else {
            if wasStreaming {
                suggestion = nil
                overlay.hide()
            }
            refreshStatus()
            return
        }
        if wasStreaming {
            if suggestion?.text != cleaned {
                suggestion = Suggestion(text: cleaned, source: source)
                overlay.show(cleaned, font: ghostFont, caret: ghostCaret, fieldFrame: self.field?.frame)
            }
            refreshStatus()
            return
        }
        // Il cursore è ancora lì?
        guard let now = FocusReader.focusedField(), CFEqual(now.element, field.element), now.caret == field.caret
        else { refreshStatus(); return }
        show(Suggestion(text: cleaned, source: source), field: now, context: context)
    }

    /// Il modello non ha finito ma è andato storto: via il pezzo mostrato.
    private func clearPartial() {
        guard streaming else { return }
        streaming = false
        suggestion = nil
        overlay.hide()
    }

    /// Hai preso (o stai scrivendo) il suggerimento a metà: il modello smette, i pezzi in arrivo non contano più.
    private func stopStreaming() {
        guard requestTask != nil || streaming else { return }
        if streaming { cutShort = true }
        requestTask?.cancel()
        requestTask = nil
        streaming = false
        generation += 1
    }

    private func clipboardIfAllowed() -> String? {
        guard prefs.clipboardContext, let text = NSPasteboard.general.string(forType: .string) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2000 else { return nil }
        return String(trimmed.prefix(500))
    }

    private func show(_ s: Suggestion, field: FocusedField, context: TextContext) {
        suggestion = s
        self.field = field
        origin = context.before
        acceptedSoFar = ""
        acceptedCurrent = false
        streaming = false
        cutShort = false
        stats.shown += 1
        let caret = FocusReader.caretBounds(field, afterNewline: context.before.last?.isNewline == true)
        ghostCaret = caret
        ghostFont = caret == nil ? nil : FocusReader.font(field)
        overlay.show(s.text, font: ghostFont, caret: caret, fieldFrame: field.frame)
        refreshStatus()
    }

    /// Dopo un tasto o una parola accettata il cursore si è spostato: il testo fantasma lo segue.
    private func reposition(after milliseconds: Int = 40) {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(milliseconds))
            guard let self, let s = self.suggestion, let field = FocusReader.focusedField() else { return }
            self.field = field
            let caret = FocusReader.caretBounds(field, afterNewline: false)
            self.overlay.show(s.text, font: caret == nil ? nil : FocusReader.font(field), caret: caret, fieldFrame: field.frame)
        }
    }

    // MARK: - Accettare

    private func acceptWord() {
        guard let s = suggestion else { return }
        let (first, rest) = s.split()
        guard !first.isEmpty else { dismiss(reason: nil); return }
        TextInserter.type(first)
        acceptedSoFar += first
        stats.acceptedWords += 1
        noteAccepted()
        prefs.addAcceptedWords(1)
        if rest.trimmingCharacters(in: .whitespaces).isEmpty {
            finishSuggestion(learn: true)
            scheduleSuggestion(delay: Self.afterAcceptDelay)
        } else {
            suggestion = Suggestion(text: rest, source: s.source)
            reposition(after: 80)   // il testo appena scritto deve arrivare all'app prima di rileggere il cursore
        }
    }

    private func acceptAll() {
        guard let s = suggestion else { return }
        TextInserter.type(s.text)
        acceptedSoFar += s.text
        stats.acceptedAll += 1
        noteAccepted()
        prefs.addAcceptedWords(s.words.count)
        finishSuggestion(learn: true)
        scheduleSuggestion(delay: Self.afterAcceptDelay)
    }

    /// Dopo un'accettazione il seguito dopo si chiede quasi subito: il tempo che il testo arrivi all'app.
    private static let afterAcceptDelay = 0.08

    private func noteAccepted() {
        guard !acceptedCurrent else { return }
        acceptedCurrent = true
        stats.acceptedSuggestions += 1
    }

    private func finishSuggestion(learn: Bool) {
        if learn, !cutShort, prefs.phraseMemory, suggestion?.source != .memory,
           TextTokens.wordCount(acceptedSoFar) >= 1 {
            memory.learn(before: origin, accepted: acceptedSoFar)
        }
        suggestion = nil
        acceptedSoFar = ""
        streaming = false
        overlay.hide()
        generation += 1
        refreshStatus()
    }

    func dismiss(reason: String?) {
        debounceTask?.cancel()
        requestTask?.cancel()
        requestTask = nil
        streaming = false
        suggestion = nil
        acceptedSoFar = ""
        overlay.hide()
        generation += 1
        refreshStatus()
    }

    // MARK: - Abbreviazioni e correzioni

    private func scheduleBoundaryFix(boundary: String) {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            self?.applyBoundaryFix(boundary: boundary)
        }
    }

    /// La parola appena finita: prima le abbreviazioni ("cmq" → "comunque"), poi le correzioni italiane.
    private func applyBoundaryFix(boundary: String) {
        guard let field = FocusReader.focusedField(), !field.isSecure,
              !prefs.isExcluded(field.bundleID), field.selection.length == 0 else { return }
        if ignoreOwnProcess, field.pid == getpid() { return }
        guard let before = FocusReader.text(before: field, max: 200), before.hasSuffix(boundary) else { return }
        if let found = Abbreviations.match(before: before, in: prefs.abbreviations) {
            if replaceWord(found.trigger, with: found.expansion, boundary: boundary, field: field, before: before) {
                stats.expansions += 1
            }
            return
        }
        guard prefs.italianCorrections, let last = ItalianRules.lastWord(before: before) else { return }
        let word = last.word
        var fixed = ItalianRules.correction(for: word)
        if fixed == nil, prefs.capitalizeSentences { fixed = ItalianRules.capitalized(word, before: last.prefix) }
        guard let fixed, fixed != word else { return }
        if replaceWord(word, with: fixed, boundary: boundary, field: field, before: before) {
            stats.corrections += 1
        }
    }

    /// Sostituisce `word`, che finisce subito prima del carattere di confine appena scritto, con `replacement`: via
    /// Accessibilità se l'app lo permette, altrimenti cancellando e riscrivendo, ma solo se nel frattempo non è
    /// cambiato niente. Vero se è andata.
    private func replaceWord(_ word: String, with replacement: String, boundary: String, field: FocusedField,
                             before: String) -> Bool {
        let boundaryUnits = boundary.utf16.count
        if FocusReader.replace(field, length: word.utf16.count, endingAt: field.caret - boundaryUnits, with: replacement,
                               keepAfter: boundaryUnits) {
            return true
        }
        guard let check = FocusReader.text(before: field, max: 200), check == before else { return false }
        TextInserter.deleteBackward(word.count + boundary.count)
        TextInserter.type(replacement + boundary)
        return true
    }

    // MARK: - Controlli dall'esterno

    func forgetPhrases() {
        memory.forgetAll()
        diag(.app, "phrase memory cleared")
    }

    func setEnabled(_ on: Bool) {
        prefs.enabled = on
        if !on { dismiss(reason: nil) }
        diag(.app, on ? "resumed" : "paused")
    }
}

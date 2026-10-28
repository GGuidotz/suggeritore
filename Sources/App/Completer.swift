// Il cuore dell'app: ascolta i tasti, aspetta che ti fermi, legge il campo, chiede un seguito (prima alla memoria e
// alle regole, poi al modello) e lo mostra in grigio. Tab accetta una parola, Maiusc-Tab tutto, Esc scarta; se scrivi
// proprio quello che era suggerito il suggerimento avanza, se scrivi altro sparisce. A fine parola applica le
// correzioni italiane. Tutto sul main actor; il modello lavora in un Task che si annulla appena riprendi a scrivere.

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
    }

    @Published private(set) var status: Status = .off
    @Published private(set) var frontApp: (bundleID: String, name: String)?
    @Published private(set) var stats = Stats()
    @Published private(set) var lastError: String?

    let prefs: Preferences
    let apple = AppleEngine()
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
    private var debounceTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    private var generation = 0
    private var bag = Set<AnyCancellable>()

    init(prefs: Preferences) {
        self.prefs = prefs
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
        startMonitorIfPossible()
        appChanged()
        if prefs.engine == .apple { apple.prewarm() }
        diag(.app, "completer started, tap \(monitor.isRunning ? "on" : "off")")
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
                acceptedSoFar += s.characters
                let rest = String(suggestion.text.dropFirst(s.characters.count))
                if rest.trimmingCharacters(in: .whitespaces).isEmpty {
                    finishSuggestion(learn: true)
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
            if prefs.italianCorrections, Self.isBoundary(s.characters) { scheduleCorrection(boundary: s.characters) }
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

    private func scheduleSuggestion() {
        debounceTask?.cancel()
        requestTask?.cancel()
        requestTask = nil
        generation += 1
        let delay = prefs.delay
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.produceSuggestion()
        }
    }

    private func produceSuggestion() {
        guard prefs.enabled, monitor.isRunning, !KeyMonitor.secureInputActive else { return }
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
        guard prefs.engine == .apple else { return }
        guard apple.unavailableReason == nil else { refreshStatus(); return }
        let request = CompletionRequest(context: context, length: prefs.length, language: LanguageGuess.code(for: before),
                                        instructions: prefs.instructions, clipboard: clipboardIfAllowed())
        let engine = apple
        requestTask = Task { [weak self] in
            let result: Result<String, Error>
            do { result = .success(try await engine.complete(request)) } catch { result = .failure(error) }
            guard !Task.isCancelled, let self, self.generation == gen else { return }
            self.requestTask = nil
            switch result {
            case .success(let raw):
                guard let cleaned = Prompting.cleanCompletion(raw, for: request) else { self.refreshStatus(); return }
                // Il cursore è ancora lì?
                guard let now = FocusReader.focusedField(), CFEqual(now.element, field.element), now.caret == field.caret
                else { self.refreshStatus(); return }
                self.show(Suggestion(text: cleaned, source: .apple), field: now, context: context)
            case .failure(let error):
                self.stats.modelFailures += 1
                self.lastError = error.localizedDescription
                diag(.engine, "model failed: \(error.localizedDescription)")
                self.refreshStatus()
            }
        }
        refreshStatus()
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
        stats.shown += 1
        let caret = FocusReader.caretBounds(field, afterNewline: context.before.last?.isNewline == true)
        overlay.show(s.text, font: caret == nil ? nil : FocusReader.font(field), caret: caret, fieldFrame: field.frame)
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
        prefs.acceptedWordsTotal += 1
        if rest.trimmingCharacters(in: .whitespaces).isEmpty {
            finishSuggestion(learn: true)
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
        prefs.acceptedWordsTotal += s.words.count
        finishSuggestion(learn: true)
    }

    private func finishSuggestion(learn: Bool) {
        if learn, prefs.phraseMemory, suggestion?.source != .memory,
           TextTokens.wordCount(acceptedSoFar) >= 1 {
            memory.learn(before: origin, accepted: acceptedSoFar)
        }
        suggestion = nil
        acceptedSoFar = ""
        overlay.hide()
        generation += 1
        refreshStatus()
    }

    func dismiss(reason: String?) {
        debounceTask?.cancel()
        requestTask?.cancel()
        requestTask = nil
        suggestion = nil
        acceptedSoFar = ""
        overlay.hide()
        generation += 1
        refreshStatus()
    }

    // MARK: - Correzioni

    private func scheduleCorrection(boundary: String) {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            self?.applyCorrection(boundary: boundary)
        }
    }

    private func applyCorrection(boundary: String) {
        guard prefs.italianCorrections, let field = FocusReader.focusedField(), !field.isSecure,
              !prefs.isExcluded(field.bundleID), field.selection.length == 0 else { return }
        if ignoreOwnProcess, field.pid == getpid() { return }
        guard let before = FocusReader.text(before: field, max: 200), before.hasSuffix(boundary) else { return }
        guard let last = ItalianRules.lastWord(before: before) else { return }
        let word = last.word
        var fixed = ItalianRules.correction(for: word)
        if fixed == nil, prefs.capitalizeSentences { fixed = ItalianRules.capitalized(word, before: last.prefix) }
        guard let fixed, fixed != word else { return }
        let boundaryUnits = boundary.utf16.count
        if FocusReader.replace(field, length: word.utf16.count, endingAt: field.caret - boundaryUnits, with: fixed, keepAfter: boundaryUnits) {
            stats.corrections += 1
            return
        }
        // Ripiego: cancella e riscrivi, ma solo se nel frattempo non è cambiato niente.
        guard let check = FocusReader.text(before: field, max: 200), check == before else { return }
        TextInserter.deleteBackward(word.count + boundary.count)
        TextInserter.type(fixed + boundary)
        stats.corrections += 1
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

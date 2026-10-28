// La guida dei primi passi: sei schermate brevi al primo avvio (e da Impostazioni › Generale o dal menu). Cosa fa
// l'app, i due permessi (chiesti qui, spiegando perché), il motore (Gemma con llama.cpp o Apple Intelligence), come si
// usa, le scelte sulla privacy, una prova dal vivo.
// Ogni scelta qui è la stessa delle impostazioni, quindi si può chiudere in qualunque momento.
// HIG (onboarding.md): breve, si impara usando, i permessi si chiedono nel momento in cui servono e spiegando perché.

import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let view = OnboardingView(model: model, prefs: model.prefs, completer: model.completer) { [weak self] in
                self?.window?.performClose(nil)
            }
            let w = TranslucentWindow.make(view, size: OnboardingView.size)
            w.delegate = self
            window = w
        }
        window?.title = L("Benvenuto in Suggeritore")
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Chiusa in qualunque modo, la guida è vista: non torna da sola. Via anche le viste.
    nonisolated func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                AppModel.shared.prefs.onboardingDone = true
                if !AppModel.shared.prefs.clipboardDecided { AppModel.shared.prefs.clipboardDecided = true }
                self?.window?.contentViewController = nil
                self?.window = nil
            }
        }
    }
}

struct OnboardingView: View {
    static let size = CGSize(width: 540, height: 620)

    var model: AppModel
    @ObservedObject var prefs: Preferences
    @ObservedObject var completer: Completer
    var finish: () -> Void

    @State private var step = 0
    @State private var accessibility = Permissions.accessibility
    @State private var inputMonitoring = Permissions.inputMonitoring
    @State private var tryText = ""
    @State private var llamaInstalled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let steps = 6

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: permissions
                case 2: engine
                case 3: howItWorks
                case 4: choices
                default: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 36)
            .padding(.top, 44)
            .transition(.opacity)
            .id(step)

            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .id(prefs.language)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            accessibility = Permissions.accessibility
            inputMonitoring = Permissions.inputMonitoring
            if accessibility, !completer.monitor.isRunning { completer.startMonitorIfPossible() }
            if step == 2 {
                completer.llama.refreshInstalled()
                llamaInstalled = completer.llama.isInstalled
            }
        }
        .onAppear { llamaInstalled = completer.llama.isInstalled }
    }

    // MARK: - Passi

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(L("Benvenuto in Suggeritore"))
                .font(.largeTitle.weight(.semibold))
                .fontDesign(.rounded)
                .multilineTextAlignment(.center)
            Text(L("Mentre scrivi, in qualunque app, ti propone il seguito in grigio. Tab per prenderlo, continuare a scrivere per ignorarlo. Tutto sul Mac: niente rete, niente dati che escono."))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            GhostPreview(written: L("Grazie per la disponibilità, ci"), ghost: L(" sentiamo la prossima settimana."),
                         accept: L("Così appare un suggerimento."))
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var permissions: some View {
        StepPage(symbol: "lock.open", title: L("Due permessi"),
                 text: L("Per vedere in che campo scrivi e appoggiarci il suggerimento, macOS chiede il permesso Accessibilità. Per vedere Tab ed Esc, su alcune versioni, anche Monitoraggio input.")) {
            PermissionRow(title: L("Accessibilità"), granted: accessibility,
                          detail: L("Indispensabile: senza, Suggeritore non può fare niente."),
                          request: { Permissions.requestAccessibility() }, open: { Permissions.openAccessibilitySettings() })
                .contentCard()
            PermissionRow(title: L("Monitoraggio input"), granted: inputMonitoring,
                          detail: L("Se dopo il primo permesso i suggerimenti compaiono, questo non serve."),
                          request: { Permissions.requestInputMonitoring() }, open: { Permissions.openInputMonitoringSettings() })
                .contentCard()
            if accessibility, completer.monitor.isRunning {
                Label(L("Tutto a posto: Suggeritore vede la tastiera."), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Palette.calm)
            } else if accessibility {
                Footnote(L("Permesso concesso ma macOS non consegna ancora i tasti: chiudi e riapri Suggeritore."))
            }
            Footnote(L("In Impostazioni di Sistema › Privacy e sicurezza trovi Suggeritore nell'elenco: accendi l'interruttore. Niente esce dal Mac."))
        }
    }

    private var engine: some View {
        StepPage(symbol: "cpu", title: L("Il motore"),
                 text: L("Gemma 3 1B è il consigliato: più preciso e più veloce; serve llama.cpp, che si installa con Homebrew, e al primo uso scarica circa 0,8 GB. Apple Intelligence è già sul Mac, senza installare niente, ma è più debole.")) {
            if llamaInstalled {
                Label(L("llama.cpp è installato: Gemma parte alla prima richiesta."), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Palette.calm)
            } else {
                LlamaInstallBox()
                    .contentCard()
            }
            AppleStatusLabel(readyText: L("Apple Intelligence è pronta: il modello gira sul Mac."))
            Picker(L("Motore"), selection: $prefs.engine) {
                Text(EngineChoice.auto.title).tag(EngineChoice.auto)
                Text(EngineChoice.gemma.title).tag(EngineChoice.gemma)
                Text(EngineChoice.apple.title).tag(EngineChoice.apple)
            }
            .pickerStyle(.segmented)
            .padding(.top, 4)
            Footnote(L("Consigliato: Automatico. Usa Gemma quando c'è llama.cpp, altrimenti Apple Intelligence. Si cambia in Impostazioni › Motori."))
        }
    }

    private var howItWorks: some View {
        StepPage(symbol: "keyboard", title: L("Come si usa"),
                 text: L("Scrivi come sempre. Dopo una breve pausa compare il seguito in grigio.")) {
            GhostPreview(written: L("Ci vediamo domani alle"), ghost: L(" 10 davanti all'ufficio."),
                         accept: L("%@ accetta una parola, %@ tutto, %@ scarta.", prefs.acceptWord.display, prefs.acceptAll.display, prefs.dismiss.display))
            Tip(symbol: "arrow.right.to.line", text: L("%@: prendi la prossima parola. Premilo più volte per andare avanti una parola alla volta.", prefs.acceptWord.display))
            Tip(symbol: "text.append", text: L("%@: prendi tutto il suggerimento.", prefs.acceptAll.display))
            Tip(symbol: "xmark", text: L("%@, o semplicemente continua a scrivere: il suggerimento sparisce.", prefs.dismiss.display))
            Tip(symbol: "pencil.line", text: L("%@ sul testo selezionato: più breve, più formale, correggi, o un'istruzione tua.", prefs.rewrite.display))
            Picker(L("Lunghezza"), selection: $prefs.length) {
                ForEach(SuggestionLength.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.top, 4)
            Footnote(L("Tasti e lunghezza si cambiano in Impostazioni › Suggerimenti."))
        }
    }

    private var choices: some View {
        StepPage(symbol: "hand.raised", title: L("Le tue scelte"),
                 text: L("Tre cose che decidi tu. Si cambiano quando vuoi.")) {
            Picker(L("Gli appunti come contesto"), selection: Binding(
                get: { prefs.clipboardContext },
                set: { prefs.clipboardContext = $0; prefs.clipboardDecided = true }
            )) {
                Text(L("No, non leggerli")).tag(false)
                Text(L("Sì, usali se c'entrano")).tag(true)
            }
            .pickerStyle(.radioGroup)
            Footnote(L("Con gli appunti il modello vede anche l'ultima cosa che hai copiato (un nome, un numero, un indirizzo) e la usa se serve al seguito. Resta sul Mac."))
            Toggle(L("Correzioni italiane in linea (\"perche\" diventa \"perché\")"), isOn: $prefs.italianCorrections)
            Toggle(L("Ricorda le frasi che accetto e riproponile"), isOn: $prefs.phraseMemory)
        }
    }

    private var ready: some View {
        StepPage(symbol: "checkmark.circle", title: L("Tutto pronto"),
                 text: L("Prova qui sotto: scrivi l'inizio di una frase e fermati un attimo.")) {
            TextField(L("Per esempio: Buongiorno Marta, ti scrivo per"), text: $tryText, axis: .vertical)
                .lineLimit(3...5)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 15))
            if !completer.monitor.isRunning {
                Footnote(L("Manca il permesso Accessibilità: torna indietro di quattro passi per concederlo."))
            }
            Tip(symbol: "menubar.rectangle", text: L("Nella barra dei menu trovi lo stato, la pausa e \"Suggerisci in questa app\" per spegnere Suggeritore dove non lo vuoi."))
            Tip(symbol: "lock", text: L("Nei campi password e nelle app con input sicuro non suggerisce mai. Gestori di password e Terminale sono esclusi in partenza."))
            Toggle(L("Apri all'accesso"), isOn: Binding(
                get: { LaunchAtLogin.isEnabled },
                set: { LaunchAtLogin.set($0) }
            ))
            .toggleStyle(.switch)
            .padding(.top, 8)
        }
    }

    // MARK: - In fondo

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<steps, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Color.primary.opacity(0.75) : Color.primary.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("Passo %d di %d", step + 1, steps))

            Spacer()

            GlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    if step > 0 {
                        Button(L("Indietro")) { go(step - 1) }
                            .glassButton()
                            .keyboardShortcut(.cancelAction)
                    }
                    Button(step == steps - 1 ? L("Inizia") : L("Avanti")) {
                        if step == steps - 1 { finish() } else { go(step + 1) }
                    }
                    .glassProminentButton()
                    .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private func go(_ next: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { step = min(max(0, next), steps - 1) }
    }
}

/// Una pagina della guida: simbolo, titolo, una frase, poi il contenuto.
private struct StepPage<Content: View>: View {
    var symbol: String
    var title: String
    var text: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.title.weight(.semibold))
                .fontDesign(.rounded)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Tip: View {
    var symbol: String
    var text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 22)
        }
        .font(.body)
    }
}

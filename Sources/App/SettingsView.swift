// Impostazioni (⌘,): sei schede sotto una barra di vetro che galleggia. Solo ciò che si cambia di rado, più
// aggiornamenti e feedback, come nelle altre app della famiglia.

import AppKit
import SwiftUI

struct SettingsView: View {
    static let size = CGSize(width: 620, height: 680)

    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences

    init(model: AppModel) {
        self.model = model
        prefs = model.prefs
    }

    var body: some View {
        Group {
            switch model.settingsTab {
            case .general: GeneralSettings(model: model, prefs: prefs, completer: model.completer)
            case .suggestions: SuggestionSettings(prefs: prefs, completer: model.completer)
            case .apps: AppsSettings(prefs: prefs, completer: model.completer)
            case .intelligence: IntelligenceSettings(prefs: prefs, completer: model.completer)
            case .updates: UpdatesSettings(updater: model.updater, prefs: prefs)
            case .feedback: FeedbackSettings(model: model)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)   // il fondo è il materiale della finestra (SettingsWindow)
        .safeAreaInset(edge: .top, spacing: 0) {
            SettingsTabBar(selection: $model.settingsTab)
                .padding(.top, 2)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .id(prefs.language)   // cambio di lingua: ridisegna tutto subito
    }
}

/// Il testo sotto una sezione.
struct Footnote: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Generale

private struct GeneralSettings: View {
    var model: AppModel
    @ObservedObject var prefs: Preferences
    @ObservedObject var completer: Completer
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?
    @State private var usage: ProcessUsage?
    @State private var accessibility = Permissions.accessibility
    @State private var inputMonitoring = Permissions.inputMonitoring

    var body: some View {
        Form {
            Section {
                Toggle(L("Suggerimenti attivi"), isOn: Binding(get: { prefs.enabled }, set: { completer.setEnabled($0) }))
                LabeledContent(L("Stato"), value: completer.status.title)
                Toggle(L("Apri all'accesso"), isOn: Binding(
                    get: { launchAtLogin },
                    set: { enabled in
                        loginError = LaunchAtLogin.set(enabled)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                ))
                if let loginError { Footnote(loginError) }
                Picker(L("Lingua"), selection: $prefs.language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
            } footer: {
                Footnote(L("La lingua è quella dell'interfaccia di Suggeritore. I suggerimenti seguono la lingua in cui stai scrivendo."))
            }

            Section {
                PermissionRow(title: L("Accessibilità"), granted: accessibility,
                              detail: L("Per leggere il campo in cui scrivi, mostrare il suggerimento e vedere Tab ed Esc."),
                              request: { Permissions.requestAccessibility() }, open: { Permissions.openAccessibilitySettings() })
                PermissionRow(title: L("Monitoraggio input"), granted: inputMonitoring,
                              detail: L("Su alcune versioni di macOS serve anche questo per vedere i tasti. Se i suggerimenti funzionano, puoi ignorarlo."),
                              request: { Permissions.requestInputMonitoring() }, open: { Permissions.openInputMonitoringSettings() })
            } header: {
                Text(L("Permessi"))
            } footer: {
                Footnote(L("Niente esce dal Mac: i permessi servono solo a leggere il campo con il fuoco e a scriverci. Dopo averli concessi, se la voce nella barra resta chiara, riapri Suggeritore."))
            }
            .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
                accessibility = Permissions.accessibility
                inputMonitoring = Permissions.inputMonitoring
                if accessibility, !completer.monitor.isRunning { completer.startMonitorIfPossible() }
            }

            Section {
                LabeledContent(L("Consumo di Suggeritore")) {
                    Text(usage.map { L("%@ di CPU · %@", Format.percent($0.cpu), Format.bytes($0.memory)) } ?? "–")
                        .monospacedDigit()
                }
                LabeledContent(L("Parole accettate da sempre"), value: Format.integer(prefs.acceptedWordsTotal))
                Button(L("Rivedi la guida iniziale")) { model.showOnboarding() }
            } footer: {
                Footnote(L("A tastiera ferma l'app non fa nulla. Il modello lavora solo dopo una pausa mentre scrivi, e si ferma appena riprendi."))
            }
            .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in usage = completer.ownUsage }
            .onAppear { usage = completer.ownUsage }
        }
    }
}

/// Una riga di permesso: nome, stato scritto e colorato, pulsanti per chiedere o aprire le impostazioni.
struct PermissionRow: View {
    var title: String
    var granted: Bool
    var detail: String
    var request: () -> Void
    var open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(granted ? Palette.calm : Color.orange)
                }
                Spacer()
                if granted {
                    Text(L("Concesso")).foregroundStyle(.secondary)
                } else {
                    Button(L("Consenti")) { request() }
                    Button(L("Apri Impostazioni di Sistema")) { open() }
                }
            }
            Footnote(detail)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(granted ? L("Concesso") : L("Non concesso"))
    }
}

// MARK: - Suggerimenti

private struct SuggestionSettings: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var completer: Completer
    @State private var forgotten = false

    var body: some View {
        Form {
            Section {
                GhostPreview(written: L("Ci vediamo domani alle"), ghost: L(" 10 davanti all'ufficio."),
                             accept: L("%@ accetta una parola, %@ tutto, %@ scarta.", prefs.acceptWord.display, prefs.acceptAll.display, prefs.dismiss.display))
                KeyBindingRecorder(title: L("Accetta una parola"), binding: $prefs.acceptWord, reset: .tab)
                KeyBindingRecorder(title: L("Accetta tutto"), binding: $prefs.acceptAll, reset: .shiftTab)
                KeyBindingRecorder(title: L("Scarta"), binding: $prefs.dismiss, reset: .escape)
                KeyBindingRecorder(title: L("Riscrivi la selezione"), binding: $prefs.rewrite, reset: .controlOptionR)
            } header: {
                Text(L("Tasti"))
            } footer: {
                Footnote(L("I tasti di accettazione valgono solo mentre un suggerimento è visibile: senza suggerimento Tab ed Esc fanno quello che fanno sempre. Se continui a scrivere, il suggerimento sparisce da solo."))
            }

            Section {
                Picker(L("Lunghezza"), selection: $prefs.length) {
                    ForEach(SuggestionLength.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Footnote(prefs.length.detail)
                LabeledContent(L("Aspetta prima di suggerire")) {
                    HStack(spacing: 10) {
                        Slider(value: $prefs.delay, in: 0.15...1.5, step: 0.05)
                            .frame(width: 180)
                            .accessibilityLabel(L("Aspetta prima di suggerire"))
                            .accessibilityValue(L("%d ms", Int(prefs.delay * 1000)))
                        Text(L("%d ms", Int(prefs.delay * 1000)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                }
                Toggle(L("Completa anche a metà riga (sperimentale)"), isOn: $prefs.midLine)
            } header: {
                Text(L("Quando e quanto"))
            } footer: {
                Footnote(L("Il suggerimento arriva dopo una pausa nella scrittura. A metà riga il seguito deve raccordarsi con il testo che c'è dopo il cursore: funziona, ma non sempre bene."))
            }

            Section {
                Toggle(L("Correzioni italiane in linea"), isOn: $prefs.italianCorrections)
                Toggle(L("Maiuscola dopo il punto"), isOn: $prefs.capitalizeSentences)
                    .disabled(!prefs.italianCorrections)
            } header: {
                Text(L("Correzioni"))
            } footer: {
                Footnote(L("Appena finisci la parola: \"perche\" diventa \"perché\", \"un pò\" diventa \"un po'\", \"qual'è\" diventa \"qual è\". Solo parole che sbagliate non vogliono dire niente; le sigle in maiuscolo non si toccano."))
            }

            Section {
                Toggle(L("Ricorda le frasi che accetto"), isOn: $prefs.phraseMemory)
                HStack {
                    Text(L("%@ seguiti ricordati", Format.integer(completer.memory.count))).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Dimentica tutto")) {
                        completer.forgetPhrases()
                        forgotten = true
                    }
                    .disabled(completer.memory.count == 0)
                }
                if forgotten { Footnote(L("Memoria svuotata.")) }
            } header: {
                Text(L("Memoria delle frasi"))
            } footer: {
                Footnote(L("I seguiti che accetti vengono legati alle due parole che li precedono e riproposti subito, senza modello, dalla seconda volta. Restano in un file sul Mac, in Application Support."))
            }
        }
    }
}

// MARK: - App

private struct AppsSettings: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var completer: Completer
    @State private var running: [NSRunningApplication] = []

    var body: some View {
        Form {
            Section {
                Toggle(L("Usa gli appunti come contesto"), isOn: $prefs.clipboardContext)
            } header: {
                Text(L("Contesto"))
            } footer: {
                Footnote(L("Con gli appunti il modello vede anche l'ultima cosa che hai copiato (nomi, numeri, indirizzi) e la usa se c'entra. Tutto resta sul Mac. Spento, gli appunti non vengono letti mai."))
            }

            Section {
                ForEach(prefs.excludedApps.sorted(by: { name(for: $0) < name(for: $1) }), id: \.self) { bundleID in
                    HStack {
                        Text(name(for: bundleID))
                        Text(bundleID).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                        Spacer()
                        Button {
                            prefs.setExcluded(bundleID, false)
                            completer.refreshStatus()
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(L("Togli %@ dalle escluse", name(for: bundleID)))
                    }
                }
                Menu(L("Aggiungi un'app aperta…")) {
                    ForEach(running.filter { !prefs.excludedApps.contains($0.bundleIdentifier ?? "") }, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "?") {
                            if let id = app.bundleIdentifier { prefs.setExcluded(id, true); completer.refreshStatus() }
                        }
                    }
                }
                .onAppear { refreshRunning() }
                Button(L("Torna all'elenco di partenza")) { prefs.resetExclusions(); completer.refreshStatus() }
            } header: {
                Text(L("App escluse"))
            } footer: {
                Footnote(L("Qui Suggeritore non legge e non scrive mai. Nei campi password e con l'input sicuro acceso non lo fa comunque, in nessuna app. Dal menu nella barra puoi spegnere l'app in cui ti trovi."))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in refreshRunning() }
    }

    private func refreshRunning() {
        running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func name(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return Exclusions.knownNames[bundleID] ?? bundleID
    }
}

// MARK: - Apple Intelligence

private struct IntelligenceSettings: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var completer: Completer

    var body: some View {
        Form {
            Section {
                Picker(L("Motore"), selection: $prefs.engine) {
                    ForEach(EngineChoice.allCases) { Text($0.title).tag($0) }
                }
                let reason = AppleEngine.unavailableReason
                Label {
                    Text(reason ?? L("Apple Intelligence è pronta: il modello gira sul Mac, niente rete.")).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: reason == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(reason == nil ? Palette.calm : Color.orange)
                }
                .font(.callout)
                if let error = completer.lastError {
                    Footnote(L("Ultimo errore del modello: %@", error))
                }
            } header: {
                Text(L("Motore"))
            } footer: {
                Footnote(L("Con \"Solo regole e memoria\" il modello non viene mai chiamato: restano le correzioni, le formule fisse e le frasi che hai accettato. Gemma, un secondo modello sul Mac, arriverà in una versione successiva."))
            }

            Section {
                TextField(L("Per esempio: tono informale, frasi corte, niente anglicismi"), text: $prefs.instructions, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text(L("Le tue istruzioni"))
            } footer: {
                Footnote(L("Una frase che vale per tutti i suggerimenti. Il modello la legge insieme al testo: tienila corta e concreta. Non scriverci dati personali: restano sul Mac, ma non servono."))
            }
        }
    }
}

// MARK: - Aggiornamenti

private struct UpdatesSettings: View {
    @ObservedObject var updater: Updater
    @ObservedObject var prefs: Preferences
    private let current = Changelog.load().first

    var body: some View {
        Form {
            Section {
                Toggle(L("Controlla automaticamente (ogni 6 ore)"), isOn: $prefs.autoCheckUpdates)
                LabeledContent(L("Versione installata"), value: updater.currentVersion)
                LabeledContent(L("Ultimo controllo")) {
                    if let last = updater.lastCheck { Text(last, style: .relative) } else { Text(L("Mai")) }
                }
                HStack {
                    Button(L("Controlla ora")) { Task { await updater.check() } }
                        .disabled(updater.state == .checking)
                    UpdateStateText(updater: updater)
                }
            }

            if updater.isUpdateAvailable {
                Section { UpdateCard(updater: updater) }
            }

            if let current {
                Section {
                    ChangelogList(entries: [current])
                    Button(L("Mostra la schermata delle novità")) { AppModel.shared.showWhatsNew() }
                } header: {
                    Text(L("Novità di questa versione"))
                }
            }
        }
    }
}

private struct UpdateStateText: View {
    @ObservedObject var updater: Updater

    var body: some View {
        switch updater.state {
        case .idle: EmptyView()
        case .checking: ProgressView().controlSize(.small)
        case .upToDate:
            Label(L("Suggeritore è aggiornato."), systemImage: "checkmark.circle.fill").foregroundStyle(Palette.calm)
        case .available(let version):
            Label(L("Disponibile la versione %@", version), systemImage: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
        case .failed(let why):
            Text(why).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Le novità della nuova versione e il comando per aggiornare.
private struct UpdateCard: View {
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if case .available(let version) = updater.state {
                Label(L("Disponibile Suggeritore %@", version), systemImage: "arrow.down.circle.fill")
                    .font(.headline)
            }
            if !updater.news.isEmpty { ChangelogList(entries: updater.news) }
            Text(L("Per aggiornare, esegui nel Terminale:")).foregroundStyle(.secondary)
            Text(updater.command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
            HStack {
                Button(L("Copia comando")) { updater.copyCommand() }
                Button(L("Aggiorna nel Terminale")) { updater.runInTerminal() }
                    .glassProminentButton()
            }
            if let error = updater.terminalError {
                Text(error).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Feedback

private struct FeedbackSettings: View {
    @ObservedObject var model: AppModel
    @State private var status: String?
    @State private var showReport = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Suggeritore").font(.title2.weight(.semibold)).fontDesign(.rounded)
                        Text(L("Versione %@", "\(SystemInfo.version) (\(SystemInfo.build))")).foregroundStyle(.secondary)
                        Text(L("Il seguito di quello che scrivi, in ogni app del Mac.")).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                FeedbackButton(symbol: "ladybug", title: L("Segnala un problema"),
                               detail: L("Su GitHub, con versione, macOS e modello del Mac già scritti.")) {
                    Feedback.openIssue(.problem)
                }
                FeedbackButton(symbol: "lightbulb", title: L("Suggerisci un'idea"),
                               detail: L("Un'app dove non funziona, una regola che manca, un modo migliore di suggerire.")) {
                    Feedback.openIssue(.idea)
                }
                FeedbackButton(symbol: "envelope", title: L("Scrivi un'email"),
                               detail: Developer.email) {
                    Feedback.composeEmail()
                }
            } header: {
                Text(L("Feedback"))
            } footer: {
                Footnote(L("GitHub è il canale preferito: le segnalazioni sono pubbliche, quindi non scrivere dati personali né il testo che stavi scrivendo. Per qualcosa di privato usa l'email."))
            }

            Section {
                HStack {
                    Button(L("Copia report")) {
                        Feedback.copyReport(model: model)
                        status = L("Report copiato: incollalo nella segnalazione.")
                    }
                    Button(L("Salva…")) { status = Feedback.saveReport(model: model) }
                    Spacer()
                    Button(showReport ? L("Nascondi") : L("Mostra")) { showReport.toggle() }
                }
                if let status { Footnote(status) }
                if showReport {
                    ScrollView {
                        Text(DiagnosticsReport.make(model: model))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 200)
                }
            } header: {
                Text(L("Diagnostica"))
            } footer: {
                Footnote(L("Il report dice versione, Mac, permessi, stato del motore, le tue scelte e i conteggi di questa sessione. Mai il testo che scrivi, mai nomi di finestre o di file."))
            }

            Section {
                DeveloperLinks()
            }
        }
    }
}

private struct FeedbackButton: View {
    var symbol: String
    var title: String
    var detail: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
    }
}

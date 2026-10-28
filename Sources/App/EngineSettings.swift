// Impostazioni › Motori: quale motore usare (Automatico, Gemma, Apple Intelligence, solo regole), lo stato di
// llama.cpp e del suo server, il modello di Gemma (tre pronti più i tuoi), lo stato di Apple Intelligence e le tue
// istruzioni. I controlli sullo stato girano solo mentre la scheda è aperta. Il riquadro per installare llama.cpp
// (LlamaInstallBox) lo usa anche la guida al primo avvio.

import AppKit
import SwiftUI

struct EngineSettings: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var completer: Completer
    @ObservedObject var llama: LlamaServer

    var body: some View {
        Form {
            EngineChoiceSection(prefs: prefs, completer: completer)
            GemmaServerSection(prefs: prefs, llama: llama)
            GemmaModelSection(prefs: prefs, llama: llama)
            CustomModelsSection(prefs: prefs)
            AppleIntelligenceSection(completer: completer)
        }
        .onAppear {
            llama.refreshInstalled()
            llama.refreshOllama()
        }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in llama.refreshInstalled() }
    }
}

// MARK: - Scelta

private struct EngineChoiceSection: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var completer: Completer

    var body: some View {
        Section {
            Picker(L("Motore"), selection: $prefs.engine) {
                ForEach(EngineChoice.allCases) { Text($0.title).tag($0) }
            }
            LabeledContent(L("In uso adesso"), value: completer.currentEngineName ?? L("Solo regole e memoria"))
            if let notice = completer.engineNotice { Footnote(notice) }
        } header: {
            Text(L("Motore"))
        } footer: {
            Footnote(L("Consigliato: Automatico. Usa Gemma quando c'è llama.cpp (o Ollama con il modello), altrimenti Apple Intelligence; mentre Gemma si avvia risponde Apple Intelligence. Con \"Solo regole e memoria\" nessun modello viene chiamato: restano correzioni, abbreviazioni, formule fisse e le frasi che hai accettato."))
        }
    }
}

// MARK: - Gemma

private struct GemmaServerSection: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var llama: LlamaServer

    var body: some View {
        Section {
            LabeledContent {
                StateLabel(ok: llama.isInstalled, text: !llama.isInstalled ? L("Non installato")
                           : LlamaServer.bundledTag.map { L("Incluso nell'app (%@)", $0) } ?? L("Installato"))
            } label: {
                Text(verbatim: "llama.cpp")
            }
            if !llama.isInstalled {
                LlamaInstallBox()
            }
            LabeledContent(L("Server")) {
                Text(serverText)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if llama.state == .stopped || llama.state.isFailed {
                    Button(L("Avvia ora")) { llama.start() }
                        .disabled(!llama.isInstalled && !llama.ollamaRunning)
                } else {
                    Button(L("Ferma")) { llama.stop() }
                }
                if llama.state.isBusy { ProgressView().controlSize(.small) }
            }
            Toggle(L("Usa Ollama se è aperto"), isOn: $prefs.useOllama)
            Toggle(L("Tieni il modello pronto"), isOn: $prefs.keepModelLoaded)
            if !prefs.keepModelLoaded || prefs.batterySaver {
                LabeledContent(L("Spegni dopo")) {
                    Stepper(value: $prefs.llamaIdleMinutes, in: 1...120, step: 1) {
                        Text(L("%d minuti senza richieste", Int(prefs.llamaIdleMinutes))).monospacedDigit()
                    }
                }
            }
            ServerPathField(prefs: prefs)
        } header: {
            Text(verbatim: "Gemma (llama.cpp)")
        } footer: {
            Footnote(L("Il server gira solo sul Mac (127.0.0.1). Con \"Tieni il modello pronto\" parte con l'app e resta caricato (circa 1 GB di memoria con Gemma 3 1B), così il primo suggerimento dopo una pausa arriva subito; altrimenti parte alla prima richiesta e si spegne dopo i minuti scelti. La prima volta scarica il modello nella cache di llama.cpp. Se Ollama è aperto e ha già il modello, si usa quello."))
        }
    }

    private var serverText: String {
        var text = llama.state.title
        if llama.state == .ready {
            text += " · " + llama.modelTitle
            if llama.backend == .ollama { text += " · " + L("via Ollama") }
        } else if llama.state == .downloading {
            let size = prefs.selectedModel.sizeHint
            if !size.isEmpty { text += " (" + size + ")" }
        }
        return text
    }
}

/// Il percorso di llama-server scelto a mano: vale quando premi Invio, non a ogni tasto (il server ripartirebbe).
private struct ServerPathField: View {
    @ObservedObject var prefs: Preferences
    @State private var draft = ""

    var body: some View {
        TextField(text: $draft, prompt: Text(L("Vuoto: lo cerca in /opt/homebrew/bin e /usr/local/bin"))) {
            Text(L("Percorso di llama-server"))
        }
        .onSubmit { commit() }
        .onAppear { draft = prefs.llamaServerPath ?? "" }
        .onDisappear { commit() }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String? = trimmed.isEmpty ? nil : trimmed
        if value != prefs.llamaServerPath { prefs.llamaServerPath = value }
    }
}

private struct GemmaModelSection: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var llama: LlamaServer

    var body: some View {
        Section {
            Picker(L("Modello"), selection: $prefs.selectedModelID) {
                ForEach(ModelCatalog.all(custom: prefs.customModels)) { entry in
                    Text(title(for: entry)).tag(entry.id)
                }
            }
            let entry = prefs.selectedModel
            if entry.isLocalFile {
                LabeledContent(L("File"), value: L("già sul Mac, nella cartella di Cotypist"))
            }
            if entry.usesRawCompletion {
                Footnote(L("Modello base: continua il testo così com'è, in modo naturale, ma non segue le istruzioni (tono, per app) e non riscrive la selezione: per quello si usa Apple Intelligence."))
            }
            if let repo = entry.hfRepo {
                LabeledContent {
                    Text(repo).textSelection(.enabled)
                } label: {
                    Text(verbatim: "Hugging Face")
                }
            }
            if let name = entry.ollamaName {
                LabeledContent {
                    HStack(spacing: 6) {
                        Text(name).textSelection(.enabled)
                        if llama.ollamaRunning {
                            StateLabel(ok: llama.ollamaHas(entry),
                                       text: llama.ollamaHas(entry) ? L("scaricato in Ollama") : L("non c'è in Ollama"))
                        }
                    }
                } label: {
                    Text(verbatim: "Ollama")
                }
            }
        } header: {
            Text(L("Modello di Gemma"))
        } footer: {
            Footnote(L("Più grande è il modello, più è preciso e più è lento: per i suggerimenti mentre scrivi basta il 1B. Con Ollama il modello va scaricato prima: ollama pull seguito dal nome."))
        }
    }

    private func title(for entry: ModelEntry) -> String {
        entry.isRecommended ? L("%@ (consigliato)", entry.titleWithSize) : entry.titleWithSize
    }
}

/// I modelli aggiunti da te: un nome, un repository Hugging Face (GGUF, per llama.cpp) e/o un nome di Ollama.
private struct CustomModelsSection: View {
    @ObservedObject var prefs: Preferences
    @State private var title = ""
    @State private var repo = ""
    @State private var ollama = ""

    var body: some View {
        Section {
            ForEach(prefs.customModels) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                        Text(detail(for: entry)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { remove(entry) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L("Togli %@", entry.title))
                }
            }
            TextField(text: $title, prompt: Text(L("Per esempio: Gemma 3 1B veloce"))) { Text(L("Nome")) }
            TextField(text: $repo, prompt: Text(L("Per esempio: ggml-org/gemma-3-1b-it-GGUF"))) { Text(L("Repository Hugging Face")) }
            TextField(text: $ollama, prompt: Text(L("Per esempio: gemma3:1b"))) { Text(L("Nome in Ollama")) }
            HStack {
                Spacer()
                Button(L("Aggiungi il modello")) { add() }
                    .disabled(ModelCatalog.custom(title: title, hfRepo: repo, ollamaName: ollama) == nil)
            }
        } header: {
            Text(L("Altri modelli"))
        } footer: {
            Footnote(L("Basta uno dei due: il repository per llama.cpp o il nome per Ollama. Il modello nuovo diventa quello scelto."))
        }
    }

    private func detail(for entry: ModelEntry) -> String {
        var parts: [String] = []
        if let repo = entry.hfRepo { parts.append(repo) }
        if let name = entry.ollamaName { parts.append("Ollama: " + name) }
        return parts.joined(separator: " · ")
    }

    private func add() {
        guard let entry = ModelCatalog.custom(title: title, hfRepo: repo, ollamaName: ollama) else { return }
        prefs.customModels.append(entry)
        prefs.selectedModelID = entry.id
        title = ""
        repo = ""
        ollama = ""
    }

    private func remove(_ entry: ModelEntry) {
        if prefs.selectedModelID == entry.id { prefs.selectedModelID = ModelCatalog.defaultID }
        prefs.customModels.removeAll { $0.id == entry.id }
    }
}

// MARK: - Apple Intelligence e istruzioni

private struct AppleIntelligenceSection: View {
    @ObservedObject var completer: Completer

    var body: some View {
        Section {
            AppleStatusLabel(readyText: L("Apple Intelligence è pronta: il modello gira sul Mac, niente rete."))
            if let error = completer.lastError {
                Footnote(L("Ultimo errore del modello: %@", error))
            }
        } header: {
            Text(L("Apple Intelligence"))
        } footer: {
            Footnote(L("Già sul Mac, senza installare niente, ma più debole e più lenta di Gemma. Legge solo gli ultimi 700 caratteri prima del cursore."))
        }
    }
}

/// Le tue istruzioni per il modello: stanno nella scheda Personalizzazione.
struct InstructionsSection: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Section {
            TextField(L("Per esempio: tono informale, frasi corte, niente anglicismi"), text: $prefs.instructions, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
        } header: {
            Text(L("Le tue istruzioni"))
        } footer: {
            Footnote(L("Una frase che vale per tutti i suggerimenti, con qualunque motore. Il modello la legge insieme al testo: tienila corta e concreta. Non scriverci dati personali: restano sul Mac, ma non servono. Per una frase che vale solo in un'app: Impostazioni › App."))
        }
    }
}

// MARK: - Pezzi condivisi

/// Uno stato con simbolo, colore e parole: il colore non è mai l'unico segnale.
struct StateLabel: View {
    var ok: Bool
    var text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? Palette.calm : Color.orange)
        }
    }
}

/// Lo stato di Apple Intelligence: pronta, o perché no.
struct AppleStatusLabel: View {
    var readyText: String

    var body: some View {
        let reason = AppleEngine.unavailableReason
        Label {
            Text(reason ?? readyText).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: reason == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(reason == nil ? Palette.calm : Color.orange)
        }
        .font(.callout)
    }
}

/// Come installare llama.cpp: il comando di Homebrew da copiare o da eseguire nel Terminale; se manca Homebrew,
/// dove trovarlo.
struct LlamaInstallBox: View {
    @State private var error: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if Homebrew.isInstalled {
                Text(L("Per installare llama.cpp, esegui nel Terminale:")).foregroundStyle(.secondary)
                Text(Homebrew.installLlamaCommand)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
                HStack {
                    Button(copied ? L("Copiato") : L("Copia comando")) {
                        Terminal.copy(Homebrew.installLlamaCommand)
                        copied = true
                    }
                    Button(L("Installa nel Terminale")) {
                        error = Terminal.run(command: Homebrew.installLlamaCommand)
                    }
                    .glassProminentButton()
                }
                if let error {
                    Text(error).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Label {
                    Text(L("Homebrew non è installato: serve per installare llama.cpp. Le istruzioni sono su brew.sh, poi torna qui."))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color.orange)
                }
                Link(destination: Homebrew.website) { Text(verbatim: "brew.sh") }
            }
        }
    }
}

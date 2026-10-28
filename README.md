# Suggeritore

Il seguito di quello che scrivi, in ogni app del Mac. [English](README.en.md)

Suggeritore vive nella barra dei menu di macOS. Mentre scrivi in un campo di testo, in qualunque app, dopo una breve
pausa compare in grigio il seguito proposto: Tab lo accetta una parola alla volta, Maiusc-Tab tutto, Esc lo scarta; se
continui a scrivere sparisce da solo. Il modello è quello sul Mac (Apple Intelligence): niente rete, niente dati che
escono, niente account.

L'idea viene da [Cotypist](https://cotypist.app); il codice è nostro, l'app è gratuita e aperta, e l'italiano è la
prima lingua.

## Cosa fa

- **Suggerimenti ovunque.** Nei campi di testo delle app native (Mail, Note, Pages, Messaggi, Safari…) e, dove
  l'app espone il cursore, anche altrove. Lunghezza a scelta (breve, media, lunga) e pausa prima di suggerire
  regolabile.
- **Tasti tuoi.** Accetta una parola, accetta tutto, scarta e riscrivi si cambiano in Impostazioni › Suggerimenti.
- **Apple Intelligence.** Il modello sul Mac, con una frase di istruzioni tue (tono, stile). Quando non c'è, restano
  le regole e la memoria.
- **Correzioni italiane in linea.** "perche" diventa "perché", "un pò" diventa "un po'", "qual'è" diventa "qual è",
  maiuscola dopo il punto. Solo parole che sbagliate non vogliono dire niente; le sigle non si toccano.
- **Memoria delle tue frasi.** I seguiti che accetti vengono ricordati sul Mac e riproposti subito, senza modello,
  dalla seconda volta. "Dimentica tutto" li cancella.
- **Riscrivi la selezione.** Ctrl-Opzione-R sul testo selezionato: più breve, più formale, più informale, correggi,
  oppure un'istruzione tua; anteprima e poi "Sostituisci".
- **Completamento a metà riga** (sperimentale): con testo dopo il cursore, il seguito si raccorda a ciò che segue.
- **Appunti come contesto**, se lo scegli: il modello vede l'ultima cosa copiata e la usa se c'entra.
- **App escluse.** Mai nei campi password e con l'input sicuro acceso; gestori di password e Terminale esclusi in
  partenza; dal menu nella barra spegni Suggeritore nell'app in cui ti trovi.

## Come funziona

Il permesso Accessibilità serve per leggere il campo con il fuoco (testo prima e dopo il cursore, posizione del cursore)
e per vedere i tasti; su alcune versioni di macOS serve anche Monitoraggio input. Il testo fantasma è un pannello
trasparente appoggiato al cursore. A tastiera ferma l'app non fa nulla: il modello lavora solo dopo una pausa mentre
scrivi e si ferma appena riprendi. Quanto pesa lo vedi in Impostazioni › Generale.

## Installazione

```sh
brew install --cask gguidotz/tap/suggeritore
```

Homebrew scarica il DMG dalla release, copia l'app in Applicazioni e toglie la quarantena (l'app non è notarizzata),
quindi niente "Apri comunque". Aggiornare: `brew upgrade --cask suggeritore`. Disinstallare:
`brew uninstall --cask suggeritore` (`--zap` cancella anche preferenze e memoria delle frasi).

Oppure compila dal codice: servono macOS 26 e gli strumenti a riga di comando (`xcode-select --install`); con Xcode
installato si compila anche l'icona Liquid Glass, se c'è.

```sh
git clone https://github.com/GGuidotz/suggeritore.git
cd suggeritore
./build.sh --install
```

Al primo avvio una guida breve spiega i permessi e le scelte. L'app controlla da sola gli aggiornamenti (ogni 6 ore,
si può spegnere) e in Impostazioni › Aggiornamenti mostra le novità e il comando per aggiornare.

## Feedback

Impostazioni › Feedback (o dal menu nella barra › Invia un feedback):

- **Segnala un problema** o **Suggerisci un'idea**: apre una issue su GitHub con versione, macOS e modello del Mac già
  scritti. È il canale preferito; le issue sono pubbliche, quindi niente dati personali né il testo che stavi scrivendo.
- **Scrivi un'email**: a giulioguidotz@yahoo.com, con gli stessi dati in fondo.
- **Diagnostica**: un report da copiare o salvare e allegare. Dice versione, Mac, permessi, stato del motore, le tue
  scelte e i conteggi della sessione; mai il testo che scrivi, mai nomi di finestre o di file.

## Limiti onesti

- Serve macOS 26 e, per i suggerimenti del modello, un Mac con Apple Intelligence attiva. Senza, restano regole,
  correzioni e memoria delle frasi.
- Le app Electron (Slack, Teams, VS Code, Notion…) e alcuni browser non sempre dicono dov'è il cursore: lì il
  suggerimento compare in una piccola pillola in basso, o il campo non si legge. Si può escludere l'app.
- Il modello di Apple ha una finestra piccola: legge gli ultimi duemila caratteri prima del cursore, non il documento
  intero. I suoi filtri possono rifiutare alcuni testi: in quel caso non compare niente.
- Le correzioni in linea cancellano e riscrivono la parola appena finita: in qualche app questo passa dalla cronologia
  di Annulla.
- L'app non è notarizzata: niente account Apple Developer. Le versioni pubblicate sono firmate con un'identità locale
  stabile, così macOS ricorda i permessi tra un aggiornamento e l'altro.

## Struttura

| Cartella | Cosa contiene |
|---|---|
| `Sources/Core` | Solo Foundation: contesto e suggerimenti, costruzione dei prompt e pulizia delle risposte, regole italiane, memoria delle frasi, formule fisse, esclusioni |
| `Sources/App/Input` | Lettura del campo con Accessibilità, tap della tastiera, inserimento del testo, testo fantasma, lingua |
| `Sources/App/Engines` | Apple Intelligence (FoundationModels) dietro il protocollo `CompletionEngine` |
| `Sources/App` | Avvio AppKit, coordinatore (Completer), riscrittura, barra dei menu, impostazioni, guida, novità, aggiornamenti, feedback, diagnostica |
| `Resources/Icon` | Icona classica (`tools/render-icon.py`) |
| `Localization` | Italiano (la chiave è il testo) e inglese |
| `tools` | Controllo delle traduzioni e della sintassi, disegno dell'icona, controllo dell'icona compilata |

Pubblicare una versione: aumenta `VERSION`, aggiungi la sezione in `CHANGELOG.md`, poi `./release.sh` (release su
GitHub con il DMG e aggiornamento del cask nel tap).

## Autore

Sviluppato da **gguidotz**: [github.com/GGuidotz/suggeritore](https://github.com/GGuidotz/suggeritore) ·
giulioguidotz@yahoo.com. Per segnalazioni e idee, meglio le [issue](https://github.com/GGuidotz/suggeritore/issues).

## Licenza

MIT. © 2026 GGuidotz.

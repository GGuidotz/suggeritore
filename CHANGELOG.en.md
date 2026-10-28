# What's New

English notes, same format as CHANGELOG.md (the Italian one is the reference). The app uses these when its language
is English; versions missing here fall back to the Italian notes.

## 0.2.0 · 2026-10-28

Gemma 3 becomes the recommended engine: more accurate, faster suggestions that appear while the model is still writing them. Everything stays on the Mac.

### New features
- **Gemma with llama.cpp.** A new engine: Gemma 3 1B, more accurate and faster than Apple Intelligence. It needs llama.cpp (installed with Homebrew, also from the guide or Settings › Engines); on first use it downloads the model, about 0.8 GB. The server runs only on your Mac, starts when you type and stops by itself after a few idle minutes.
- **Automatic.** The default engine: Gemma when llama.cpp is there, otherwise Apple Intelligence, otherwise rules and memory. While Gemma starts, the others answer, without waiting.
- **Ollama.** If Ollama is open and already has the model (for example gemma3:1b), Suggeritore uses it instead of starting its own server. You can turn this off in Settings › Engines.
- **More models.** Gemma 3 1B, 4B and 12B ready to choose, plus the ones you add with a Hugging Face repository or an Ollama name.
- **Cotypist's model.** If you have Cotypist, its Gemma 3 1B base model shows up in the catalog as recommended and works right away, with nothing to download. Base models continue the text naturally; instruction-tuned ones also follow your instructions and rewrite the selection.
- **Statistics from Cotypist.** In Settings › General you can add the words accepted so far in Cotypist to the counter. Its memories are encrypted and stay its own.
- **Instructions per app.** One sentence for the model that applies only in one app, in Settings › Apps, with three recommended profiles you accept with a button: formal Mail, chatty Messages, concise Notes.
- **Abbreviations.** Type an abbreviation and then a space: it becomes the full text ("btw" becomes "by the way", ";sign" your signature). You choose them in Settings › Suggestions; none is active by default.
- **Status at a glance.** At the top of Settings › General: the state, the engine in use, words accepted today and all time, accepted suggestions and the average response time. The same view will go into Cocaine's island.

### Improvements
- **The continuation appears as it arrives.** The grey text shows up with the first words and fills in as it goes, with Gemma and with Apple Intelligence: the wait feels shorter.
- **Faster Apple Intelligence.** It reads the last 700 characters instead of two thousand, always picks the most likely word and gets shorter instructions: it answers sooner and wanders less.
- **Settings › Engines.** The Apple Intelligence tab becomes Engines: engine choice, llama.cpp and server status (start, stop, minutes before stopping), model, Apple Intelligence and your instructions.
- **First-run guide.** A new step, "The engine": what changes between Gemma and Apple Intelligence and how to install llama.cpp, with the command to copy or run in Terminal.
- **Menu bar.** The status line also names the engine ("Ready · Gemma 3 1B") and says so while Gemma starts or downloads the model.
- **Rewrite the selection with Gemma.** Rewriting uses the same engine as suggestions.
- **Diagnostics.** The report also lists the engine in use, server status, selected model and average response time; never paths or text.

## 0.1.0 · 2026-10-28

First version: what you are about to write, suggested in grey in any Mac app, all on the Mac.

### New features
- **Suggestions everywhere.** While you type in a text field, after a short pause the proposed continuation appears in grey. Tab accepts the next word, Shift-Tab the whole sentence, Esc dismisses it; keep typing and it goes away by itself. Keys and length are in Settings › Suggestions.
- **Apple Intelligence.** The engine is the model on your Mac: no network, nothing leaves the Mac. When it is unavailable, the rules stay.
- **Inline Italian corrections.** Accents and apostrophes fixed as soon as you finish the word ("perche" becomes "perché", "un pò" becomes "un po'"), with a switch.
- **Memory of your phrases.** The continuations you accept are remembered on the Mac and offered again instantly, without the model; one button forgets everything.
- **Rewrite the selection.** Ctrl-Option-R on selected text: shorter, more formal, more casual, fix it, or your own instruction, with a preview before replacing.
- **Mid-line completion.** With text after the cursor, the suggestion joins what follows (experimental, with a switch).
- **Your instructions.** In Settings › Apple Intelligence one sentence that applies to every suggestion, for example the tone you prefer.
- **Excluded apps.** Never in password fields or apps with secure input; password managers and Terminal excluded by default; any app can be switched off from the menu bar.
- **First-run guide, what's new, updates and feedback.** As in the other apps of the family: permissions explained when needed, what's new after each update, update checks from GitHub, reports with your Mac's details already filled in.

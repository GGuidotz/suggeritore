# What's New

English notes, same format as CHANGELOG.md (the Italian one is the reference). The app uses these when its language
is English; versions missing here fall back to the Italian notes.

## 0.3.0 · 2026-10-28

Suggeritore becomes Type_w/Me: faster suggestions, context from the screen, an encrypted typing history that learns your words, and llama.cpp built into the app. Everything stays on the Mac.

### New features
- **Type_w/Me.** The app's new name. On first launch it brings over Suggeritore's settings, instructions, abbreviations and phrase memory; macOS asks again for Accessibility and Input Monitoring, once. You can move the old app to the Trash.
- **llama.cpp included.** On Apple silicon Macs llama-server ships inside the app: Gemma works without Homebrew. Homebrew's, or a path of your own, still works.
- **Context from the screen.** If you turn it on in Settings › Apps, the model reads the text of the window you are writing in (the email you are replying to, the page you are looking at), recognized on your Mac every few seconds and never on every key. The text stays in memory and is never saved. It needs the Screen Recording permission.
- **Personalization.** A new tab: the typing history records what you write, encrypted on your Mac with the key in the Keychain, also where you accept no suggestion (you can turn that off); you can view it and delete it per app. With "Word choice" suggestions use your own texts from the same app to match your words. Off by default.
- **Your instructions with base models too.** With Cotypist's model (a base model) your instructions, per-app instructions, your texts, the screen and the clipboard reach the model as a header of the text to continue: before, it ignored them.
- **Maximum words.** A slider from 1 to 20 instead of the length choice; at 1 it completes only the word you are typing, never the next one: spelling help without suggestions on what to write.
- **Typos.** If the word you are typing already looks misspelled, no suggestion: it would extend the mistake. Turn it off in Settings › Suggestions.
- **Battery mode.** On battery (or in Low Power Mode) the pause grows by half, the screen is not read and the model stops after the chosen idle minutes.
- **Context from the app.** The model reads, through Accessibility, the title and text of the window you are writing in (the email or chat you are replying to, the page) and writes the continuation as a reply in that conversation. No extra permissions, in memory only, on by default; turn it off in Settings › Apps. The context stays fixed for the same field, so the prompt stays in the cache.

### Improvements
- **Faster suggestions.** The text sent to Gemma keeps the same beginning for hundreds of keys and at most 1,200 characters, and llama-server keeps Gemma 3's full cache with a single slot: the already processed prompt is reused instead of redone on every request.
- **Shorter pause.** 120 ms instead of 350: the request is cancelled anyway if you keep typing. If you had the old default, you move to the new one.
- **Model always ready.** Gemma starts with the app and when the Mac wakes up and stays loaded (about 1 GB with the 1B model): the first suggestion after a break does not wait for it to start. Turn it off in Settings › Engines.
- **The next one.** After you accept a suggestion, the following one is requested right away.
- **Timing diagnostics.** The report shows how long reading the field, the first text and the full answer take, how many prompt tokens come from the cache and how many tokens per second; never text.
- **Your instructions** move from Engines to Personalization.
- **Length that adapts.** With the base model the suggestion goes on while the model is sure of the next word and stops at the first uncertain one, within the maximum of the chosen length: no made-up tails and no stops halfway.
- **Grey text everywhere.** The suggestion always appears after the caret, like the text you type, and wraps from the start of the line when it does not fit. Where the field does not tell where the caret is, no more box above the text.
- **No random continuations.** If the model is not sure of the very first word it suggests nothing, and a continuation made only of digits or punctuation is not shown. From the clipboard the base model gets only written text.
- **No stalls after a long suggestion.** After you accept a suggestion, the next one waits until the inserted text is really in the field; an extra Tab right after does not move the caret to another field.

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

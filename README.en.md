# Suggeritore

What you are about to write, in every Mac app. [Italiano](README.md)

Suggeritore lives in the macOS menu bar. While you type in a text field, in any app, after a short pause the proposed
continuation appears in grey: Tab accepts it one word at a time, Shift-Tab all of it, Esc dismisses it; keep typing and
it goes away by itself. The model is the one on your Mac (Apple Intelligence): no network, nothing leaves the Mac, no
account.

The idea comes from [Cotypist](https://cotypist.app); the code is ours, the app is free and open, and Italian is the
first language.

## What it does

- **Suggestions everywhere.** In the text fields of native apps (Mail, Notes, Pages, Messages, Safari…) and, where the
  app exposes the cursor, elsewhere too. Length of your choice (short, medium, long) and adjustable pause.
- **Your keys.** Accept one word, accept everything, dismiss and rewrite can be changed in Settings › Suggestions.
- **Apple Intelligence.** The on-device model, with one sentence of your own instructions (tone, style). When it isn't
  available, rules and memory remain.
- **Inline Italian corrections.** "perche" becomes "perché", "un pò" becomes "un po'", "qual'è" becomes "qual è",
  capital letter after a period. Only words that mean nothing when misspelled; acronyms are left alone.
- **Memory of your phrases.** The continuations you accept are remembered on the Mac and offered again instantly,
  without the model, from the second time on. "Forget everything" clears them.
- **Rewrite the selection.** Ctrl-Option-R on selected text: shorter, more formal, more casual, fix it, or your own
  instruction; preview, then "Replace".
- **Mid-line completion** (experimental): with text after the cursor, the continuation joins what follows.
- **Clipboard as context**, if you choose so: the model sees the last thing you copied and uses it when relevant.
- **Excluded apps.** Never in password fields or with secure input on; password managers and Terminal excluded by
  default; from the menu bar you can turn Suggeritore off in the app you're in.

## How it works

The Accessibility permission is needed to read the focused field (text before and after the cursor, cursor position)
and to see keys; on some macOS versions Input Monitoring is needed too. The ghost text is a transparent panel placed at
the cursor. When the keyboard is idle the app does nothing: the model works only after a pause while you type and stops
as soon as you resume. Its footprint is shown in Settings › General.

## Installation

```sh
brew install --cask gguidotz/tap/suggeritore
```

Homebrew downloads the DMG from the release, copies the app to Applications and removes the quarantine flag (the app is
not notarized), so no "Open anyway". Update: `brew upgrade --cask suggeritore`. Uninstall:
`brew uninstall --cask suggeritore` (`--zap` also removes preferences and the phrase memory).

Or build from source: macOS 26 and the command line tools (`xcode-select --install`) are required.

```sh
git clone https://github.com/GGuidotz/suggeritore.git
cd suggeritore
./build.sh --install
```

On first launch a short guide explains permissions and choices. The app checks for updates on its own (every 6 hours,
can be turned off) and Settings › Updates shows what's new and the command to update.

## Feedback

Settings › Feedback (or menu bar › Send feedback):

- **Report a problem** or **Suggest an idea**: opens a GitHub issue with version, macOS and Mac model already filled
  in. This is the preferred channel; issues are public, so no personal data and not the text you were typing.
- **Write an email**: to giulioguidotz@yahoo.com, with the same details at the bottom.
- **Diagnostics**: a report to copy or save and attach. It lists version, Mac, permissions, engine state, your choices
  and the session's counters; never the text you type, never window or file names.

## Honest limits

- Requires macOS 26 and, for model suggestions, a Mac with Apple Intelligence on. Without it, rules, corrections and
  phrase memory remain.
- Electron apps (Slack, Teams, VS Code, Notion…) and some browsers don't always say where the cursor is: there the
  suggestion shows in a small pill at the bottom, or the field can't be read. The app can be excluded.
- Apple's model has a small window: it reads the last two thousand characters before the cursor, not the whole
  document. Its filters may refuse some texts: then nothing appears.
- Inline corrections delete and retype the word you just finished: in some apps this goes through Undo history.
- The app is not notarized: no Apple Developer account. Released builds are signed with a stable local identity, so
  macOS remembers the permissions across updates.

## Structure

| Folder | Contents |
|---|---|
| `Sources/Core` | Foundation only: context and suggestions, prompt building and answer cleanup, Italian rules, phrase memory, fixed phrases, exclusions |
| `Sources/App/Input` | Reading the field with Accessibility, keyboard tap, text insertion, ghost text, language |
| `Sources/App/Engines` | Apple Intelligence (FoundationModels) behind the `CompletionEngine` protocol |
| `Sources/App` | AppKit startup, coordinator (Completer), rewrite, menu bar, settings, guide, what's new, updates, feedback, diagnostics |
| `Resources/Icon` | Classic icon (`tools/render-icon.py`) |
| `Localization` | Italian (the key is the text) and English |
| `tools` | Translation and syntax checks, icon drawing, compiled-icon check |

Publishing a version: bump `VERSION`, add the section to `CHANGELOG.md`, then `./release.sh` (GitHub release with
the DMG and cask update in the tap).

## Author

Developed by **gguidotz**: [github.com/GGuidotz/suggeritore](https://github.com/GGuidotz/suggeritore) ·
giulioguidotz@yahoo.com. For reports and ideas, the [issues](https://github.com/GGuidotz/suggeritore/issues) are best.

## License

MIT. © 2026 GGuidotz.

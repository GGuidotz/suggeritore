#!/bin/zsh
# Pubblica una versione, come What's Going On e Nod:
#   1. ./build.sh --dmg
#   2. release GitHub v<versione> con il DMG e le note prese da CHANGELOG.md (serve `gh auth login`)
#   3. aggiorna version e sha256 del cask, qui e nel clone del tap, e lo pubblica
# Prima: aumenta VERSION e aggiungi in cima a CHANGELOG.md la sezione "## <versione> · <data>".
# Repo (cambiabili): SGR_APP_REPO=GGuidotz/typewithme  SGR_TAP_DIR=~/Developer/homebrew-tap
set -euo pipefail
cd "${0:A:h}"
die() { echo "$*" >&2; exit 1; }

APP_REPO=${SGR_APP_REPO:-GGuidotz/typewithme}
TAP_DIR=${SGR_TAP_DIR:-$HOME/Developer/homebrew-tap}
VERSION=$(tr -d '[:space:]' < VERSION)
CASK=packaging/homebrew/Casks/typewithme.rb

command -v gh >/dev/null || die "Serve GitHub CLI: brew install gh && gh auth login"
[ -z "$(git status --porcelain -- .)" ] || die "Ci sono modifiche non salvate in git: fai prima il commit."
[ "$(git branch --show-current)" = main ] || die "Il rilascio parte da main: git checkout main && git pull."
gh release view "v$VERSION" --repo "$APP_REPO" >/dev/null 2>&1 && die "La release v$VERSION esiste già: aumenta VERSION."

./build.sh --dmg
# Chi installa non deve aver bisogno di Homebrew: senza llama-server incluso la release non parte.
[ -x build/TypeWithMe.app/Contents/Helpers/llama/llama-server ] \
  || die "llama-server non è nell'app (vedi packaging/llama.cpp-version e la rete): la release non parte."
DMG="dist/TypeWithMe-$VERSION.dmg"
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
section() { awk -v v="$VERSION" '$0 ~ "^## "v" " {f=1; next} /^## / {f=0} f' "$1"; }
# Note della release: in inglese se c'è la versione inglese, poi l'italiano; i gruppi con i nomi delle note di rilascio.
NOTES_IT=$(section CHANGELOG.md | sed -e 's/^### Novità/### New features/' -e 's/^### Miglioramenti/### Improvements/' \
  -e 's/^### Correzioni/### Bug fixes/' -e 's/^### Sicurezza/### Security/' -e 's/^### Problemi noti/### Known issues/')
NOTES_EN=$([ -f CHANGELOG.en.md ] && section CHANGELOG.en.md || true)
if [ -n "$NOTES_EN" ]; then
  NOTES="$NOTES_EN"$'\n\n---\n\n## Italiano\n'"$NOTES_IT"
else
  NOTES="$NOTES_IT"
fi

gh release create "v$VERSION" "$DMG" --repo "$APP_REPO" --title "Type_w/Me $VERSION" --notes "$NOTES"

sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
git add "$CASK" && git commit -m "Cask typewithme $VERSION" -- "$CASK" >/dev/null || true
git push || true

if [ -d "$TAP_DIR/.git" ]; then
  git -C "$TAP_DIR" pull --ff-only
  mkdir -p "$TAP_DIR/Casks"
  cp "$CASK" "$TAP_DIR/Casks/typewithme.rb"
  # Al primo rilascio la riga di Type_w/Me nella tabella del README del tap, dopo l'ultima.
  if [ -f "$TAP_DIR/README.md" ] && ! grep -q '`typewithme`' "$TAP_DIR/README.md"; then
    ROW='| `typewithme` | [Type_w/Me](https://github.com/GGuidotz/typewithme): il seguito di ciò che scrivi, in grigio, in qualunque app, con modelli che girano sul Mac |'
    LAST=$(grep -n '^| `' "$TAP_DIR/README.md" | tail -n 1 | cut -d: -f1)
    if [ -n "$LAST" ]; then
      awk -v row="$ROW" -v last="$LAST" '{ print } NR == last { print row }' "$TAP_DIR/README.md" > "$TAP_DIR/README.md.new"
      mv "$TAP_DIR/README.md.new" "$TAP_DIR/README.md"
      git -C "$TAP_DIR" add README.md
    fi
  fi
  git -C "$TAP_DIR" add Casks/typewithme.rb
  git -C "$TAP_DIR" commit -m "typewithme $VERSION" >/dev/null
  git -C "$TAP_DIR" push
  echo "Tap aggiornato."
else
  echo "Tap non trovato in $TAP_DIR: copia a mano $CASK in Casks/ del repo homebrew-tap."
fi
echo "Pubblicato Type_w/Me $VERSION. Installazione: brew install --cask gguidotz/tap/typewithme"

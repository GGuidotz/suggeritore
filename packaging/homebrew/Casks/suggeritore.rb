# frozen_string_literal: true

# Cask di Suggeritore per il tap GGuidotz/homebrew-tap. Version e sha256 li aggiorna release.sh.
cask "suggeritore" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/GGuidotz/suggeritore/releases/download/v#{version}/Suggeritore-#{version}.dmg"
  name "Suggeritore"
  desc "Menu bar autocomplete for every Mac app, powered by on-device models"
  homepage "https://github.com/GGuidotz/suggeritore"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :tahoe"

  app "Suggeritore.app"

  postflight do
    # L'app non è notarizzata (niente account Apple Developer): togliere la quarantena evita "Apri comunque".
    system_command "/usr/bin/xattr",
                   args:         ["-dr", "com.apple.quarantine", "#{appdir}/Suggeritore.app"],
                   must_succeed: false
  end

  uninstall quit: "local.suggeritore.app"

  zap trash: [
    "~/Library/Preferences/local.suggeritore.app.plist",
    "~/Library/Application Support/Suggeritore",
  ]

  caveats <<~EOS
    Suggeritore lives in the menu bar and needs two permissions, asked at first launch:
    Accessibility (to read the field you type in and show the suggestion) and Input Monitoring
    (to see Tab and Esc). Nothing leaves your Mac.
  EOS
end

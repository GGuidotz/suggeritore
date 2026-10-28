// Dove Type_w/Me non scrive mai: gestori di password, terminali, finestre di sistema. L'elenco di partenza si può
// cambiare dalle impostazioni e dal menu nella barra ("In questa app").

import Foundation

enum Exclusions {
    static let defaults: [String] = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.agilebits.onepassword-osx",
        "com.bitwarden.desktop", "com.lastpass.LastPass", "com.dashlane.Dashlane", "com.apple.keychainaccess",
        "com.apple.Passwords", "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
        "com.github.wez.wezterm", "net.kovidgoyal.kitty", "org.alacritty", "com.apple.systempreferences",
        "com.apple.loginwindow", "com.apple.SecurityAgent", "com.apple.ScreenSaver.Engine",
    ]

    /// Un nome leggibile per le app dell'elenco che potrebbero non essere installate (così l'elenco si capisce).
    static let knownNames: [String: String] = [
        "com.1password.1password": "1Password", "com.agilebits.onepassword7": "1Password 7",
        "com.agilebits.onepassword-osx": "1Password 6", "com.bitwarden.desktop": "Bitwarden",
        "com.lastpass.LastPass": "LastPass", "com.dashlane.Dashlane": "Dashlane",
        "com.apple.keychainaccess": "Accesso Portachiavi", "com.apple.Passwords": "Password",
        "com.apple.Terminal": "Terminale", "com.googlecode.iterm2": "iTerm2", "dev.warp.Warp-Stable": "Warp",
        "com.github.wez.wezterm": "WezTerm", "net.kovidgoyal.kitty": "kitty", "org.alacritty": "Alacritty",
        "com.apple.systempreferences": "Impostazioni di Sistema", "com.apple.loginwindow": "Finestra di login",
        "com.apple.SecurityAgent": "Richieste di sicurezza", "com.apple.ScreenSaver.Engine": "Salvaschermo",
    ]
}

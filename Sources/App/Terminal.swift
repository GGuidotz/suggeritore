// Eseguire un comando nel Terminale, quando lo chiedi tu: per aggiornare Type_w/Me (Updater) e per installare
// llama.cpp con Homebrew (guida e Impostazioni › Motori). La prima volta macOS chiede il permesso Automazione.
// Più dove si trovano Homebrew e i suoi programmi.

import AppKit
import Foundation

@MainActor
enum Terminal {
    /// Apre il Terminale ed esegue `command`. nil se è andata, altrimenti un messaggio per chi usa l'app.
    @discardableResult
    static func run(command: String) -> String? {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "tell application \"Terminal\"\nactivate\ndo script \"\(escaped)\"\nend tell"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            diag(.app, "run in Terminal failed: \(error[NSAppleScript.errorNumber] ?? "?")")
            return L("Il Terminale non ha eseguito il comando: copialo e incollalo tu. (%@)",
                     (error[NSAppleScript.errorMessage] as? String) ?? "?")
        }
        return nil
    }

    static func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}

/// Homebrew e i programmi che installa: Apple Silicon in /opt/homebrew, Intel in /usr/local.
enum Homebrew {
    static let binDirectories = ["/opt/homebrew/bin", "/usr/local/bin"]

    static var isInstalled: Bool {
        binDirectories.contains { FileManager.default.isExecutableFile(atPath: $0 + "/brew") }
    }

    static let website = URL(string: "https://brew.sh")!
    static let installLlamaCommand = "brew install llama.cpp"
}

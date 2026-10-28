// Il nome dell'app e gli identificativi in un posto solo. Il nome visibile ha lo slash, che nei nomi di file e nei
// percorsi non può stare: su disco l'app si chiama TypeWithMe. I valori "legacy" servono solo alla migrazione da
// Suggeritore (Sources/App/Migration.swift).

import Foundation

enum AppInfo {
    /// Il nome che si legge nell'interfaccia.
    static let name = "Type_w/Me"
    /// Il nome tecnico: file .app, eseguibile, CFBundleName, DMG, nomi di file.
    static let fileName = "TypeWithMe"
    static let bundleID = "com.gguidotz.typewithme"
    /// Il repository GitHub (proprietario/nome).
    static let repo = "GGuidotz/typewithme"
    /// Il nome del cask Homebrew.
    static let caskName = "typewithme"
    /// La cartella in Application Support.
    static let supportFolder = "TypeWithMe"

    /// Come si chiamava l'app prima (fino alla 0.2.x): identificativo e cartella da cui migrare.
    static let legacyBundleID = "local.suggeritore.app"
    static let legacySupportFolder = "Suggeritore"
}

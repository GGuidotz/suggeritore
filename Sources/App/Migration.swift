// Migrazione da Suggeritore (il nome di prima, fino alla 0.2.x): l'app ha cambiato nome e identificativo, quindi
// macOS la tratta come un'app nuova, con altre preferenze, un'altra cartella in Application Support e permessi da
// concedere di nuovo. Una volta sola, all'avvio e prima che nascano Preferences e AppModel, si copiano le
// preferenze e la memoria delle frasi della vecchia app. La vecchia app e i suoi dati restano dove sono.

import Foundation

enum Migration {
    private static let doneKey = "migratedFromSuggeritore"

    /// Esegue la migrazione se non è già stata fatta. Restituisce true se ha copiato qualcosa.
    /// L'app non è nel sandbox, quindi legge le preferenze della vecchia app dal loro dominio.
    @discardableResult
    static func runIfNeeded(defaults: UserDefaults = .standard, fileManager fm: FileManager = .default) -> Bool {
        guard !defaults.bool(forKey: doneKey) else { return false }
        defaults.set(true, forKey: doneKey)

        var migrated = false

        // Preferenze: solo le chiavi che la nuova app non ha ancora (dominio persistito, senza i valori di sistema).
        if let old = defaults.persistentDomain(forName: AppInfo.legacyBundleID), !old.isEmpty {
            for (key, value) in old where defaults.object(forKey: key) == nil && key != doneKey {
                defaults.set(value, forKey: key)
                migrated = true
            }
        }

        // Memoria delle frasi e altri file: la cartella si copia solo se la nuova non esiste.
        if let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let old = base.appendingPathComponent(AppInfo.legacySupportFolder, isDirectory: true)
            let new = base.appendingPathComponent(AppInfo.supportFolder, isDirectory: true)
            if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) {
                do {
                    try fm.copyItem(at: old, to: new)
                    migrated = true
                } catch {
                    // Non è grave: si riparte da una memoria vuota.
                }
            }
        }

        // macOS chiede i permessi di nuovo per il nuovo identificativo: la guida li rimostra.
        if migrated { defaults.set(false, forKey: "onboardingDone") }
        return migrated
    }
}

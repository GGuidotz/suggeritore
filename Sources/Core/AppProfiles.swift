// Le istruzioni per app: una frase per il modello che vale solo in quell'app (Mail formale, Messaggi da chat). Tre
// profili consigliati, proposti nelle impostazioni ma attivi solo se li accetti. Solo Foundation.

import Foundation

enum AppProfiles {
    struct Profile {
        let bundleID: String
        let name: String
        let instruction: String
    }

    static var recommended: [Profile] {
        [
            Profile(bundleID: "com.apple.mail", name: "Mail", instruction: L("Tono formale e cortese, frasi complete.")),
            Profile(bundleID: "com.apple.MobileSMS", name: L("Messaggi"), instruction: L("Tono informale e breve, come in chat.")),
            Profile(bundleID: "com.apple.Notes", name: L("Note"), instruction: L("Tono neutro, appunti sintetici.")),
        ]
    }

    /// I profili consigliati aggiunti a quelli che hai già, senza toccare le frasi che hai scritto tu.
    static func merged(into current: [String: String]) -> [String: String] {
        var out = current
        for profile in recommended where (out[profile.bundleID] ?? "").isEmpty {
            out[profile.bundleID] = profile.instruction
        }
        return out
    }

    /// Vero se manca almeno uno dei profili consigliati.
    static func canAddRecommended(to current: [String: String]) -> Bool {
        recommended.contains { (current[$0.bundleID] ?? "").isEmpty }
    }
}

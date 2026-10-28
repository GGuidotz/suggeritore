// Confronto numerico tra versioni ("0.10.0" > "0.9.2"). Lo usano aggiornamenti e schermata delle novità.

import Foundation

struct Version: Comparable {
    let parts: [Int]
    init(_ string: String) { parts = string.split(separator: ".").map { Int($0) ?? 0 } }

    static func < (a: Version, b: Version) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    static func == (a: Version, b: Version) -> Bool { !(a < b) && !(b < a) }
}

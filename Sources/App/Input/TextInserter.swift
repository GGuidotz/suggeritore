// Scrive nel campo in primo piano come se fosse la tastiera: eventi con la stringa Unicode (a pezzi di 20 unità, il
// limite dell'API), marchiati perché il nostro tap li ignori. Più il tasto Cancella per togliere, e un incolla con
// gli appunti rimessi a posto, per i testi lunghi dove digitare sarebbe lento.

import AppKit

enum TextInserter {
    /// Scrive `text` nell'app in primo piano.
    static func type(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            let chunk = Array(units[index..<Swift.min(index + 20, units.count)])
            index += chunk.count
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { continue }
            down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            up.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            mark(down); mark(up)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// Preme un tasto (per esempio Cancella, o ⌘V).
    static func press(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        mark(down); mark(up)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    static func deleteBackward(_ count: Int) {
        for _ in 0..<Swift.max(0, count) { press(keyCode: 51) }
    }

    /// Incolla `text` e dopo mezzo secondo rimette negli appunti quello che c'era (solo testo semplice).
    static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        press(keyCode: 9, flags: .maskCommand)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pasteboard.clearContents()
            if let previous { pasteboard.setString(previous, forType: .string) }
        }
    }

    private static func mark(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: KeyMonitor.ownEventMarker)
    }
}

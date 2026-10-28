// Il tap sulla tastiera (CGEventTap): vede ogni tasto prima dell'app che lo riceve, così Tab ed Esc, quando c'è un
// suggerimento, li prendiamo noi e non arrivano all'app. Tutto il resto passa. I tasti che scriviamo noi
// (TextInserter) portano un marchio e vengono ignorati. Un clic del mouse fa sparire il suggerimento.
// Se macOS spegne il tap (è lento a rispondere), lo riaccendiamo. Con l'input sicuro acceso (campi password,
// Terminale con l'eco spento) macOS non consegna i tasti: lo controlliamo prima di suggerire.

import AppKit
import Carbon.HIToolbox

struct KeyStroke {
    let keyCode: UInt16
    let flags: CGEventFlags
    let characters: String

    var hasCommandOrControl: Bool { flags.contains(.maskCommand) || flags.contains(.maskControl) }

    /// Un carattere che finisce nel testo (lettera, cifra, spazio, segno), non un tasto di comando o una freccia.
    var isPrintable: Bool {
        guard let scalar = characters.unicodeScalars.first, !hasCommandOrControl else { return false }
        if scalar.value < 0x20 || scalar.value == 0x7F { return false }
        if (0xF700...0xF8FF).contains(scalar.value) { return false }   // frecce, funzione
        return true
    }

    var isBackspace: Bool { keyCode == 51 }
    var isReturn: Bool { keyCode == 36 || keyCode == 76 }
}

enum KeyDecision { case pass, swallow }

@MainActor
final class KeyMonitor {
    /// Il marchio dei tasti che scriviamo noi, nel campo userData degli eventi.
    nonisolated static let ownEventMarker: Int64 = 0x5347_5249

    var onKeyDown: (@MainActor (KeyStroke) -> KeyDecision)?
    var onMouseDown: (@MainActor () -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    /// Vero con l'input sicuro acceso: lì macOS non ci fa vedere i tasti (e noi non dobbiamo suggerire).
    static var secureInputActive: Bool { IsSecureEventInputEnabled() }

    /// Crea il tap. Falso se macOS lo rifiuta: manca il permesso Accessibilità (o Monitoraggio input).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: keyMonitorCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        source = runLoopSource
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        if type == .leftMouseDown || type == .rightMouseDown {
            onMouseDown?()
            return pass
        }
        guard type == .keyDown else { return pass }
        if event.getIntegerValueField(.eventSourceUserData) == Self.ownEventMarker { return pass }
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        var length = 0
        var units = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &units)
        let characters = String(utf16CodeUnits: units, count: Swift.min(length, 4))
        let stroke = KeyStroke(keyCode: keyCode, flags: event.flags, characters: characters)
        switch onKeyDown?(stroke) ?? .pass {
        case .pass: return pass
        case .swallow: return nil
        }
    }
}

/// La funzione C che macOS chiama per ogni evento: gira sul run loop principale, quindi sul main actor.
private let keyMonitorCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<KeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    var result: Unmanaged<CGEvent>? = Unmanaged.passUnretained(event)
    MainActor.assumeIsolated { result = monitor.handle(type: type, event: event) }
    return result
}

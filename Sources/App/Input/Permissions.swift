// I due permessi che servono: Accessibilità (leggere il campo con il fuoco, inserire il testo, intercettare i tasti)
// e Monitoraggio input (vedere i tasti, su alcune versioni di macOS richiesto a parte). Si chiedono nella guida,
// spiegando perché, e si controllano quando serve. Con la firma locale stabile macOS li ricorda tra una build e l'altra.

import AppKit
import ApplicationServices

enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }

    /// Mostra la richiesta di macOS (una volta sola per sessione, poi rimanda alle Impostazioni di Sistema).
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static var inputMonitoring: Bool { CGPreflightListenEventAccess() }

    @discardableResult
    static func requestInputMonitoring() -> Bool { CGRequestListenEventAccess() }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}

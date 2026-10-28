// Corrente o batteria: a batteria (o in Risparmio energia) l'app chiede meno al Mac, se chi la usa lo vuole.
// Una lettura costa poco (IOKit), si fa solo quando serve: niente notifiche, niente timer.

import Foundation
import IOKit.ps

enum Power {
    nonisolated(unsafe) private static var cached: (date: Date, value: Bool)?

    /// Vero se il Mac va a batteria in questo momento (letto al più ogni 30 secondi: si chiede a ogni tasto).
    static var onBattery: Bool {
        if let cached, Date().timeIntervalSince(cached.date) < 30 { return cached.value }
        let value = readOnBattery()
        cached = (Date(), value)
        return value
    }

    private static func readOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return false }
        guard let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPSBatteryPowerValue
    }

    /// A batteria o con Risparmio energia acceso.
    static var shouldSave: Bool { onBattery || ProcessInfo.processInfo.isLowPowerModeEnabled }
}

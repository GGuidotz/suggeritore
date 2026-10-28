// Diagnostica: un registro breve di ciò che succede (permessi, motore, aggiornamenti) e un report in testo semplice
// da allegare a una segnalazione. Solo in memoria, mai dati personali: niente testo scritto, niente nomi di finestre
// o di file, niente app aperte. Solo stati e conteggi.

import AppKit
import Foundation

enum DiagCategory: String {
    case app, permissions, engine, update, feedback
}

@MainActor
final class DiagnosticsLog: ObservableObject {
    static let shared = DiagnosticsLog()

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let category: DiagCategory
        let message: String
    }

    @Published private(set) var entries: [Entry] = []

    func add(_ category: DiagCategory, _ message: String) {
        entries.append(Entry(date: Date(), category: category, message: message))
        if entries.count > 200 { entries.removeFirst(entries.count - 200) }
    }

    nonisolated static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }
}

/// Scorciatoia per scrivere nel registro da qualsiasi punto del codice sul main actor.
@MainActor
func diag(_ category: DiagCategory, _ message: String) {
    DiagnosticsLog.shared.add(category, message)
}

enum SystemInfo {
    /// "Mac14,2"
    static var model: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    static var macOS: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    static var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    static var version: String { info["CFBundleShortVersionString"] as? String ?? "?" }
    static var build: String { info["CFBundleVersion"] as? String ?? "?" }
    static var commit: String { info["SGRGitCommit"] as? String ?? "?" }

    /// Una riga per le email e le segnalazioni: "Suggeritore 0.1.0 (12) · macOS 26.1 · Mac14,2 · it".
    static var oneLine: String {
        "Suggeritore \(version) (\(build)) · macOS \(macOS) · \(model) · \(Localization.effectiveCode)"
    }
}

enum DiagnosticsReport {
    @MainActor
    static func make(model: AppModel) -> String {
        var out: [String] = []
        func section(_ title: String) { out.append(""); out.append("## \(title)") }
        func row(_ key: String, _ value: String) { out.append("- \(key): \(value)") }
        func yesNo(_ b: Bool) -> String { b ? "yes" : "no" }

        let prefs = model.prefs, completer = model.completer
        out.append("# Suggeritore diagnostics")
        row("Generated", DiagnosticsLog.stamp(Date()))

        section("App")
        row("Version", "\(SystemInfo.version) (build \(SystemInfo.build), commit \(SystemInfo.commit))")
        row("Icon", SystemInfo.info["SGRIconTier"] as? String ?? "?")
        row("Installed via", Updater.channel == .homebrew ? "Homebrew" : "source build")
        row("Language", "\(prefs.language.rawValue) → \(Localization.effectiveCode)")

        section("Mac")
        row("Model", SystemInfo.model)
        row("macOS", "\(SystemInfo.macOS) (\(ProcessInfo.processInfo.operatingSystemVersionString))")
        row("Architecture", SystemInfo.architecture)

        section("Permissions")
        row("Accessibility", yesNo(Permissions.accessibility))
        row("Input monitoring", yesNo(Permissions.inputMonitoring))
        row("Key tap running", yesNo(completer.monitor.isRunning))
        row("Secure input active now", yesNo(KeyMonitor.secureInputActive))

        section("Engine")
        row("Choice", prefs.engine.rawValue)
        row("Apple Intelligence", AppleEngine.unavailableReason ?? "available")
        row("Status", "\(completer.status)")
        if let error = completer.lastError { row("Last model error", error) }

        section("Preferences")
        row("Enabled", yesNo(prefs.enabled))
        row("Length", prefs.length.rawValue)
        row("Delay", "\(Int(prefs.delay * 1000)) ms")
        row("Keys", "word \(prefs.acceptWord.display), all \(prefs.acceptAll.display), dismiss \(prefs.dismiss.display), rewrite \(prefs.rewrite.display)")
        row("Mid-line", yesNo(prefs.midLine))
        row("Italian corrections", "\(yesNo(prefs.italianCorrections)), capitalize \(yesNo(prefs.capitalizeSentences))")
        row("Phrase memory", "\(yesNo(prefs.phraseMemory)), \(completer.memory.count) entries")
        row("Clipboard as context", yesNo(prefs.clipboardContext))
        row("Excluded apps", "\(prefs.excludedApps.count)")
        row("Custom instructions", prefs.instructions.isEmpty ? "none" : "\(prefs.instructions.count) characters")
        row("Automatic update check", yesNo(prefs.autoCheckUpdates))

        section("Counters (this session)")
        let s = completer.stats
        row("Suggestions shown", "\(s.shown)")
        row("Accepted word by word", "\(s.acceptedWords)")
        row("Accepted whole", "\(s.acceptedAll)")
        row("Dismissed", "\(s.dismissed)")
        row("From memory or rules", "\(s.memoryHits)")
        row("Corrections", "\(s.corrections)")
        row("Model failures", "\(s.modelFailures)")
        if let own = completer.ownUsage { row("This app now", "\(Format.percent(own.cpu)) CPU, \(Format.bytes(own.memory))") }

        section("Updates")
        row("State", "\(model.updater.state)")
        row("Last check", model.updater.lastCheck.map(DiagnosticsLog.stamp) ?? "never")

        section("Log")
        let entries = DiagnosticsLog.shared.entries.suffix(60)
        if entries.isEmpty { out.append("(empty)") }
        for e in entries { out.append("\(DiagnosticsLog.stamp(e.date)) [\(e.category.rawValue)] \(e.message)") }
        return out.joined(separator: "\n") + "\n"
    }

    static var suggestedFileName: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return "Suggeritore-diagnostics-\(f.string(from: Date())).txt"
    }
}

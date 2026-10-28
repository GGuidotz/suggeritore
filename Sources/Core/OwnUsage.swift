// Quanto pesa Suggeritore stessa: CPU (percento di un core, come Monitoraggio Attività) e memoria.
// Una sola chiamata sul proprio processo: costa quasi nulla. Come in What's Going On.

import Foundation

struct ProcessUsage {
    var cpu: Double
    var memory: UInt64
}

final class OwnUsageReader {
    private var previous: (cpu: UInt64, at: UInt64)?
    private let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(max(1, info.numer)), UInt64(max(1, info.denom)))
    }()

    func read() -> ProcessUsage? {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V2, $0) }
        }
        guard result == 0 else { return nil }
        let cpuTime = (info.ri_user_time + info.ri_system_time) * timebase.numer / timebase.denom
        let now = DispatchTime.now().uptimeNanoseconds
        defer { previous = (cpuTime, now) }
        guard let previous, now > previous.at, cpuTime >= previous.cpu else { return nil }
        let cpu = Double(cpuTime - previous.cpu) / Double(now - previous.at) * 100
        return ProcessUsage(cpu: cpu, memory: info.ri_phys_footprint)
    }
}

enum Format {
    static func bytes(_ value: UInt64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        return f.string(fromByteCount: Int64(value))
    }

    static func percent(_ value: Double) -> String {
        let f = NumberFormatter()
        f.locale = Localization.locale
        f.maximumFractionDigits = value < 10 ? 1 : 0
        f.minimumFractionDigits = 0
        return (f.string(from: NSNumber(value: value)) ?? "0") + "%"
    }

    static func integer(_ value: Int) -> String {
        let f = NumberFormatter()
        f.locale = Localization.locale
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

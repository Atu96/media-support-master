import Darwin
import Foundation
import IOKit

struct ResourceSnapshot: Sendable {
    var appMemoryMB: Double = 0
    var engineMemoryMB: Double = 0
    var appCPUPercent: Double = 0
    var engineCPUPercent: Double = 0
    var gpuPercent: Double = 0
    var temperatureCelsius: Double?
    var engineCommand: String = ""
    var childCount: Int = 0

    var summaryLine: String {
        let metrics = metricsFragment
        if engineCommand.isEmpty {
            return "\(metrics)App \(formatMB(appMemoryMB)) · engine nghỉ"
        }
        return "\(metrics)App \(formatMB(appMemoryMB)) · Engine \(formatMB(engineMemoryMB)) · \(engineCommand)"
    }

    private var metricsFragment: String {
        var parts: [String] = []
        parts.append("CPU \(formatPercent(appCPUPercent))")
        if engineCPUPercent > 0.5 {
            parts.append("job \(formatPercent(engineCPUPercent))")
        }
        parts.append("GPU \(formatPercent(gpuPercent))")
        if let temperatureCelsius {
            parts.append(String(format: "%.0f°C", temperatureCelsius))
        }
        return parts.joined(separator: " · ") + " · "
    }

    private func formatMB(_ value: Double) -> String {
        String(format: "%.0f MB", value)
    }

    private func formatPercent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }
}

@MainActor
final class SystemResourceMonitor: ObservableObject {
    static let shared = SystemResourceMonitor()

    @Published private(set) var snapshot = ResourceSnapshot()

    private var timer: Timer?
    private var trackedPID: Int32?

    private init() {}

    func setEnginePID(_ pid: Int32?) {
        trackedPID = pid
        if let pid {
            Self.primeCPUSamples(appPID: ProcessInfo.processInfo.processIdentifier, trackedPID: pid)
        }
        refresh()
    }

    func startPolling(every seconds: TimeInterval = 2) {
        stopPolling()
        Self.primeCPUSamples(appPID: ProcessInfo.processInfo.processIdentifier, trackedPID: trackedPID)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func shutdownForQuit() {
        stopPolling()
        trackedPID = nil
        terminateAllChildProcesses()
    }

    /// Process con trực tiếp của `parentPID` (dùng khi kill cây job).
    static func childPIDs(of parentPID: pid_t) -> [pid_t] {
        rebuildPPIDMapIfNeeded()
        return ppidByChild.compactMap { child, ppid in
            ppid == parentPID ? child : nil
        }
    }

    func terminateAllChildProcesses() {
        let appPID = ProcessInfo.processInfo.processIdentifier
        for pid in Self.descendantPIDs(of: appPID) {
            kill(pid, SIGTERM)
        }
        usleep(80_000)
        for pid in Self.descendantPIDs(of: appPID) where kill(pid, 0) == 0 {
            kill(pid, SIGKILL)
        }
    }

    func refresh() {
        let appPID = ProcessInfo.processInfo.processIdentifier
        snapshot.appMemoryMB = Self.memoryMB(for: appPID)
        snapshot.appCPUPercent = Self.cpuPercent(for: appPID) ?? Self.lastKnownCPU[appPID] ?? 0

        if let trackedPID {
            let tree = Self.processTreeStats(root: trackedPID)
            snapshot.engineMemoryMB = tree.memoryMB
            snapshot.engineCPUPercent = tree.cpuPercent
            snapshot.engineCommand = tree.label
            snapshot.childCount = tree.count
        } else {
            let tree = Self.engineStats(for: appPID)
            snapshot.engineMemoryMB = tree.memoryMB
            snapshot.engineCPUPercent = tree.cpuPercent
            snapshot.engineCommand = tree.label
            snapshot.childCount = tree.count
        }

        snapshot.gpuPercent = Self.gpuUtilizationPercent()
        snapshot.temperatureCelsius = Self.socTemperatureCelsius()
    }

    // MARK: - Process tree cache

    private static let pidMapTTL: TimeInterval = 3
    private static var ppidByChild: [pid_t: pid_t] = [:]
    private static var ppidMapBuiltAt: Date?

    private static func rebuildPPIDMapIfNeeded() {
        let now = Date()
        if let builtAt = ppidMapBuiltAt, now.timeIntervalSince(builtAt) < pidMapTTL {
            return
        }

        let count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard count > 0 else { return }

        var buffer = [pid_t](repeating: 0, count: Int(count))
        let filled = proc_listpids(
            UInt32(PROC_ALL_PIDS),
            0,
            &buffer,
            Int32(MemoryLayout<pid_t>.size * buffer.count)
        )
        guard filled > 0 else { return }

        let myUID = getuid()
        var map: [pid_t: pid_t] = [:]
        let pidCount = Int(filled) / MemoryLayout<pid_t>.size
        map.reserveCapacity(pidCount)

        for index in 0..<pidCount {
            let pid = buffer[index]
            guard pid > 0 else { continue }
            var info = proc_bsdinfo()
            let size = MemoryLayout<proc_bsdinfo>.size
            let bytes = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))
            guard bytes == size, info.pbi_uid == myUID else { continue }
            map[pid] = pid_t(info.pbi_ppid)
        }

        ppidByChild = map
        ppidMapBuiltAt = now
    }

    private static func descendantPIDs(of root: pid_t, maxDepth: Int = 16) -> [pid_t] {
        rebuildPPIDMapIfNeeded()
        var result: [pid_t] = []
        var frontier = [root]
        var depth = 0

        while !frontier.isEmpty, depth < maxDepth {
            var next: [pid_t] = []
            for parent in frontier {
                for (child, ppid) in ppidByChild where ppid == parent && child != parent {
                    if !result.contains(child) {
                        result.append(child)
                        next.append(child)
                    }
                }
            }
            frontier = next
            depth += 1
        }
        return result
    }

    private static func processTreeStats(root: pid_t) -> (memoryMB: Double, cpuPercent: Double, label: String, count: Int) {
        let pids = uniquePIDs([root] + descendantPIDs(of: root))
        guard !pids.isEmpty else { return (0, 0, "", 0) }

        var memory: Double = 0
        var cpu: Double = 0
        for pid in pids {
            memory += memoryMB(for: pid)
            cpu += cpuPercent(for: pid) ?? lastKnownCPU[pid] ?? 0
        }
        return (memory, cpu, commandName(for: root), pids.count)
    }

    private static func engineStats(for appPID: pid_t) -> (memoryMB: Double, cpuPercent: Double, label: String, count: Int) {
        let pids = uniquePIDs(
            descendantPIDs(of: appPID).filter { pid in
                commandName(for: pid) != "MediaSupportMac"
            }
        )
        guard !pids.isEmpty else { return (0, 0, "", 0) }

        var memory: Double = 0
        var cpu: Double = 0
        var names: [String] = []
        for pid in pids {
            memory += memoryMB(for: pid)
            cpu += cpuPercent(for: pid) ?? lastKnownCPU[pid] ?? 0
            let name = commandName(for: pid)
            if !names.contains(name) {
                names.append(name)
            }
        }
        let label = names.prefix(3).joined(separator: ", ")
        return (memory, cpu, label, pids.count)
    }

    private static func uniquePIDs(_ pids: [pid_t]) -> [pid_t] {
        var seen = Set<pid_t>()
        var result: [pid_t] = []
        result.reserveCapacity(pids.count)
        for pid in pids where seen.insert(pid).inserted {
            result.append(pid)
        }
        return result
    }

    private static func primeCPUSamples(appPID: pid_t, trackedPID: pid_t?) {
        _ = cpuPercent(for: appPID)
        if let trackedPID {
            for pid in uniquePIDs([trackedPID] + descendantPIDs(of: trackedPID)) {
                _ = cpuPercent(for: pid)
            }
        } else {
            for pid in descendantPIDs(of: appPID) {
                _ = cpuPercent(for: pid)
            }
        }
    }

    // MARK: - Per-process metrics

    private static func memoryMB(for pid: pid_t) -> Double {
        var info = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size
        let bytes = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(size))
        guard bytes == size else { return 0 }
        return Double(info.pti_resident_size) / 1024 / 1024
    }

    private static var lastCPU: [pid_t: (time: UInt64, stamp: Date)] = [:]
    private static var lastKnownCPU: [pid_t: Double] = [:]

    private static func cpuPercent(for pid: pid_t) -> Double? {
        var info = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size
        let bytes = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(size))
        guard bytes == size else { return nil }

        let total = info.pti_total_user + info.pti_total_system
        let now = Date()
        defer { lastCPU[pid] = (total, now) }

        guard let previous = lastCPU[pid] else { return nil }
        let delta = Double(total &- previous.time)
        let interval = now.timeIntervalSince(previous.stamp)
        guard interval > 0.05 else { return nil }

        let percent = min(800, (delta / interval) / 10_000_000)
        lastKnownCPU[pid] = percent
        return percent
    }

    private static func commandName(for pid: pid_t) -> String {
        let bufferSize = UInt32(256)
        var name = [UInt8](repeating: 0, count: Int(bufferSize))
        let len = proc_name(pid, &name, bufferSize)
        guard len > 0 else { return "pid \(pid)" }
        return String(cString: name)
    }

    // MARK: - GPU / temperature (IOKit, poll nhẹ)

    private static let sensorTTL: TimeInterval = 3
    private static var lastSensorRead: Date?
    private static var cachedGPU: Double = 0
    private static var cachedTemperature: Double?

    private static func gpuUtilizationPercent() -> Double {
        refreshSlowSensorsIfNeeded()
        return cachedGPU
    }

    private static func socTemperatureCelsius() -> Double? {
        refreshSlowSensorsIfNeeded()
        return cachedTemperature
    }

    private static func refreshSlowSensorsIfNeeded() {
        let now = Date()
        if let lastSensorRead, now.timeIntervalSince(lastSensorRead) < sensorTTL {
            return
        }
        lastSensorRead = now
        cachedGPU = readGPUUtilizationPercent()
        cachedTemperature = readSOCTemperatureCelsius()
    }

    private static func readGPUUtilizationPercent() -> Double {
        guard let match = IOServiceMatching("IOAccelerator") else { return cachedGPU }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == KERN_SUCCESS else {
            return cachedGPU
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        var peak: Double = 0

        while service != 0 {
            defer { IOObjectRelease(service) }
            if let property = IORegistryEntryCreateCFProperty(
                service,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] {
                peak = max(peak, numericPercent(property["Device Utilization %"]))
                peak = max(peak, numericPercent(property["Renderer Utilization %"]))
                peak = max(peak, numericPercent(property["Tiler Utilization %"]))
            }
            service = IOIteratorNext(iterator)
        }

        return peak
    }

    private static func numericPercent(_ value: Any?) -> Double {
        if let intValue = value as? Int { return Double(intValue) }
        if let doubleValue = value as? Double { return doubleValue }
        if let number = value as? NSNumber { return number.doubleValue }
        return 0
    }

    private static func readSOCTemperatureCelsius() -> Double? {
        SMCReader.shared.readTemperatureCelsius()
    }
}

// MARK: - AppleSMC (best-effort, không poll liên tục)

private final class SMCReader {
    static let shared = SMCReader()

    private let conn: io_connect_t?
    private var keyCache: [String: (type: UInt32, size: UInt32)] = [:]

    private init() {
        guard let match = IOServiceMatching("AppleSMC") else {
            conn = nil
            return
        }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == KERN_SUCCESS else {
            conn = nil
            return
        }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else {
            conn = nil
            return
        }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else {
            conn = nil
            return
        }
        conn = connection
    }

    func readTemperatureCelsius() -> Double? {
        guard conn != nil else { return nil }

        let candidates = ["TC0P", "TCXC", "TCMX", "Tp0C", "Te05", "Te0P", "TG0P"]
        var best: Double?
        for key in candidates {
            guard let value = readTemperature(for: key), value > 10, value < 120 else { continue }
            best = max(best ?? value, value)
        }
        return best
    }

    private func readTemperature(for key: String) -> Double? {
        guard let bytes = readBytes(for: key) else { return nil }
        guard let info = keyCache[key] else { return nil }
        return decodeTemperature(type: info.type, bytes: bytes)
    }

    private func readBytes(for key: String) -> [UInt8]? {
        guard let conn else { return nil }

        if keyCache[key] == nil {
            var input = SMCKeyData()
            input.key = SMCKeyData.fourCC(key)
            input.result = SMCKeyData.cmdReadKeyInfo
            guard let output = call(conn: conn, input: &input) else { return nil }
            keyCache[key] = (output.keyInfo.dataType, output.keyInfo.dataSize)
            input.keyInfo = output.keyInfo
            input.result = SMCKeyData.cmdReadBytes
            guard let data = call(conn: conn, input: &input) else { return nil }
            return data.payloadBytes
        }

        var input = SMCKeyData()
        input.key = SMCKeyData.fourCC(key)
        input.keyInfo.dataType = keyCache[key]!.type
        input.keyInfo.dataSize = keyCache[key]!.size
        input.result = SMCKeyData.cmdReadBytes
        guard let output = call(conn: conn, input: &input) else { return nil }
        return output.payloadBytes
    }

    private func call(conn: io_connect_t, input: inout SMCKeyData) -> SMCKeyData? {
        var output = SMCKeyData()
        var size = MemoryLayout<SMCKeyData>.size
        let result = IOConnectCallStructMethod(conn, 2, &input, size, &output, &size)
        guard result == KERN_SUCCESS else { return nil }
        return output
    }

    private func decodeTemperature(type: UInt32, bytes: [UInt8]) -> Double? {
        let label = SMCKeyData.fourCCString(type)
        switch label {
        case "sp78", "sp87":
            guard bytes.count >= 2 else { return nil }
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(raw) / 256.0
        case "fpe2", "fp1f", "fp88":
            guard bytes.count >= 2 else { return nil }
            return Double((Int(bytes[0]) * 256 + Int(bytes[1])) >> 2) / 64.0
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            return Double(bytes.withUnsafeBytes { $0.load(as: Float.self) })
        default:
            return nil
        }
    }
}

private struct SMCKeyData {
    static let cmdReadKeyInfo: UInt8 = 9
    static let cmdReadBytes: UInt8 = 5

    var key: UInt32 = 0
    var vers: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0, 0, 0, 0, 0)
    var pLimitData: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
    var keyInfo: (dataSize: UInt32, dataType: UInt32, dataAttributes: UInt8) = (0, 0, 0)
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )

    var payloadBytes: [UInt8] {
        let count = Int(keyInfo.dataSize)
        return withUnsafeBytes(of: data8) { Array($0.prefix(count)) }
    }

    static func fourCC(_ key: String) -> UInt32 {
        let bytes = Array(key.utf8.prefix(4))
        var value: UInt32 = 0
        for (index, byte) in bytes.enumerated() {
            value |= UInt32(byte) << (8 * (3 - index))
        }
        return value
    }

    static func fourCCString(_ value: UInt32) -> String {
        String(
            format: "%c%c%c%c",
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        )
    }
}
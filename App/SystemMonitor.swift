import Darwin
import Foundation
import Observation

/// Samples system-wide CPU and memory load once per `sample()` call.
@Observable
final class SystemMonitor {
    private(set) var cpuPercent = 0
    private(set) var memoryPercent = 0
    private var previousTicks: [UInt32]?

    func sample() {
        cpuPercent = readCPU() ?? cpuPercent
        memoryPercent = readMemory() ?? memoryPercent
    }

    /// Busy share of all cores since the previous sample.
    private func readCPU() -> Int? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        let ticks = (0..<Int(cpuCount) * states).map { UInt32(bitPattern: info[$0]) }
        defer { previousTicks = ticks }
        guard let previous = previousTicks, previous.count == ticks.count else { return nil }
        var busy: UInt64 = 0, total: UInt64 = 0
        for core in 0..<Int(cpuCount) {
            for state in 0..<states {
                let delta = UInt64(ticks[core * states + state] &- previous[core * states + state])
                total += delta
                if state != Int(CPU_STATE_IDLE) { busy += delta }
            }
        }
        return total == 0 ? nil : Int((Double(busy) / Double(total) * 100).rounded())
    }

    /// Memory in use (active, wired, compressed) as a share of physical memory.
    private func readMemory() -> Int? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        let used = pages * UInt64(getpagesize())
        return Int((Double(used) / Double(ProcessInfo.processInfo.physicalMemory) * 100).rounded())
    }
}

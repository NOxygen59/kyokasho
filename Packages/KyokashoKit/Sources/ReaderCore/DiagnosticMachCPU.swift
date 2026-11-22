// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Darwin
import Foundation

/// Le total inclut les fils morts entre deux relevés ; le classement utilise l'estimation récente de Mach.
public struct DiagnosticMachCPU {
    private var previous: (time: TimeInterval, cpu: TimeInterval)?
    public init() {}

    /// Lit le compteur même si le fil tourne. L'appelant conserve le droit Mach pendant la lecture.
    public static func threadCPUSeconds(_ thread: thread_t) -> TimeInterval? {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.user_time.seconds) + Double(info.system_time.seconds)
            + Double(info.user_time.microseconds + info.system_time.microseconds) / 1_000_000
    }

    public mutating func sample(mainID: UInt64, samplerQueue: String? = nil) -> (percent: Double?, threads: [DiagnosticCPULog.ThreadLoad], cost: DiagnosticCPULog.Cost, complete: Bool) {
        let start = ProcessInfo.processInfo.systemUptime
        let cpuStart = ThreadCPU.seconds()
        var usage = rusage()
        var percent: Double?
        if getrusage(RUSAGE_SELF, &usage) == 0 {
            let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
            if let previous, start > previous.time, cpu >= previous.cpu {
                percent = 100 * (cpu - previous.cpu) / (start - previous.time)
            }
            previous = (start, cpu)
        } else {
            previous = nil
        }
        let threads = Self.threadLoads(mainID: mainID, samplerQueue: samplerQueue)
        let spent = max(0, ThreadCPU.seconds() - cpuStart)
        return (percent, threads ?? [], .init(wall: ProcessInfo.processInfo.systemUptime - start, cpu: spent), threads != nil)
    }

    private static func threadLoads(mainID: UInt64, samplerQueue: String?) -> [DiagnosticCPULog.ThreadLoad]? {
        var buffer: thread_act_array_t?
        var count: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &buffer, &count) == KERN_SUCCESS, let buffer else { return nil }
        let ports = UnsafeBufferPointer(start: buffer, count: Int(count))
        defer {
            // task_threads rend à la fois des droits d'envoi et un tableau alloué par le noyau.
            for port in ports { mach_port_deallocate(mach_task_self_, port) }
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: buffer)), vm_size_t(ports.count * MemoryLayout<thread_t>.stride))
        }
        let ownPort = pthread_mach_thread_np(pthread_self())
        return ports.compactMap { port in
            var basic = thread_basic_info()
            var basicCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.stride)
            let read = withUnsafeMutablePointer(to: &basic) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) {
                    thread_info(port, thread_flavor_t(THREAD_BASIC_INFO), $0, &basicCount)
                }
            }
            guard read == KERN_SUCCESS, basic.flags & TH_FLAGS_IDLE == 0 else { return nil }
            var info = thread_identifier_info_data_t()
            var size = mach_msg_type_number_t(MemoryLayout<thread_identifier_info_data_t>.size / MemoryLayout<integer_t>.stride)
            let identity = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                    thread_info(port, thread_flavor_t(THREAD_IDENTIFIER_INFO), $0, &size)
                }
            }
            // Un port Mach n'est pas une identité stable. dispatch_qaddr n'est jamais déréférencé.
            guard identity == KERN_SUCCESS else { return nil }
            let percent = 100 * Double(basic.cpu_usage) / Double(TH_USAGE_SCALE)
            let name = percent >= DiagnosticThreads.threshold ? threadName(port) : nil
            let role: DiagnosticCPULog.ThreadRole?
            if port == ownPort { role = .sampler }
            else if info.thread_id == mainID { role = .main }
            else { role = publicRole(name) }
            let cpu = Double(basic.user_time.seconds) + Double(basic.system_time.seconds)
                + Double(basic.user_time.microseconds + basic.system_time.microseconds) / 1_000_000
            return .init(id: info.thread_id, percent: percent, role: role, name: name,
                         queue: port == ownPort ? samplerQueue : nil, cpuSeconds: cpu)
        }
    }

    private static func threadName(_ port: thread_t) -> String? {
        guard let thread = pthread_from_mach_thread_np(port) else { return nil }
        var name = [CChar](repeating: 0, count: 64)
        guard pthread_getname_np(thread, &name, name.count) == 0 else { return nil }
        return name.withUnsafeBufferPointer { String(validatingUTF8: $0.baseAddress!) }
    }

    private static func publicRole(_ name: String?) -> DiagnosticCPULog.ThreadRole? {
        switch name {
        case "com.apple.uikit.eventfetch-thread": return .eventFetcher
        case "WebThread": return .webThread
        case "JavaScriptCore bmalloc scavenger": return .javascriptGC
        default: return nil
        }
    }
}

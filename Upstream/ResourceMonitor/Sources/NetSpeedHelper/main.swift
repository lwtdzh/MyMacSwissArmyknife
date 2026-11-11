import Darwin
import Foundation
import IOKit

struct Counters {
    var download: UInt64 = 0
    var upload: UInt64 = 0
}

struct DiskCounters {
    var read: UInt64 = 0
    var write: UInt64 = 0
}

struct CPUCounters {
    var active: UInt64 = 0
    var total: UInt64 = 0
}

struct NetworkDeltaParser {
    private var buffer = Data()
    private var hasBaseline = false
    private var readingDeltas = false

    mutating func consume(_ data: Data) -> Counters {
        buffer.append(data)
        var counters = Counters()
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[..<newline], as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(...newline)

            if line.hasPrefix(",") {
                // The first nettop frame contains existing totals, even with -d.
                readingDeltas = hasBaseline
                hasBaseline = true
                continue
            }
            guard readingDeltas else { continue }
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3, !fields[0].isEmpty,
                  let download = UInt64(fields[1]), let upload = UInt64(fields[2])
            else { continue }
            counters.download += download
            counters.upload += upload
        }
        return counters
    }
}

final class ExternalNetworkSampler {
    private let process = Process()
    private let readHandle: FileHandle
    private let queue = DispatchQueue(label: "com.mymacswissarmyknife.ResourceMonitor.network")
    private var parser = NetworkDeltaParser()
    private var pending = Counters()

    init() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        readHandle = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        let writeHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        defer { try? writeHandle.close() }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = [
            "-P", "-d", "-t", "external", "-L", "0", "-s", "1", "-n", "-x",
            "-J", "bytes_in,bytes_out"
        ]
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["LC_ALL": "C"]
        ) { _, new in new }
        // A PTY makes nettop flush each frame instead of buffering small samples.
        process.standardOutput = writeHandle
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()

        readHandle.readabilityHandler = { [weak self] handle in
            var storage = Data(count: 65_536)
            let received = storage.withUnsafeMutableBytes {
                Darwin.read(handle.fileDescriptor, $0.baseAddress, $0.count)
            }
            if received < 0, errno == EINTR { return }
            guard received > 0 else {
                handle.readabilityHandler = nil
                return
            }
            let data = Data(storage.prefix(received))
            self?.queue.async { [weak self] in
                guard let self else { return }
                let delta = self.parser.consume(data)
                self.pending.download += delta.download
                self.pending.upload += delta.upload
            }
        }
    }

    func takeCounters() -> Counters {
        // Let the host restart the helper if its continuous collector exits.
        guard process.isRunning else { exit(EXIT_FAILURE) }
        return queue.sync {
            let result = pending
            pending = Counters()
            return result
        }
    }

    func stop() {
        readHandle.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }
}

func cpuCounters() -> CPUCounters {
    var cpuCount: natural_t = 0
    var cpuInfo: processor_info_array_t?
    var infoCount: mach_msg_type_number_t = 0
    guard
        host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &infoCount
        ) == KERN_SUCCESS,
        let cpuInfo
    else {
        return CPUCounters()
    }
    defer {
        vm_deallocate(
            mach_task_self_,
            vm_address_t(UInt(bitPattern: cpuInfo)),
            vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
        )
    }

    var counters = CPUCounters()
    for cpu in 0..<Int(cpuCount) {
        let offset = cpu * Int(CPU_STATE_MAX)
        let user = UInt64(cpuInfo[offset + Int(CPU_STATE_USER)])
        let system = UInt64(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
        let nice = UInt64(cpuInfo[offset + Int(CPU_STATE_NICE)])
        let idle = UInt64(cpuInfo[offset + Int(CPU_STATE_IDLE)])
        counters.active += user + system + nice
        counters.total += user + system + nice + idle
    }
    return counters
}

func memoryUsagePercent() -> UInt64 {
    var statistics = vm_statistics64()
    var count = mach_msg_type_number_t(
        MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
    )
    let result = withUnsafeMutablePointer(to: &statistics) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return 0 }

    let usedPages = UInt64(statistics.active_count)
        + UInt64(statistics.wire_count)
        + UInt64(statistics.compressor_page_count)
    let usedBytes = usedPages * UInt64(vm_kernel_page_size)
    let totalBytes = ProcessInfo.processInfo.physicalMemory
    guard totalBytes > 0 else { return 0 }
    return min(100, UInt64((Double(usedBytes) / Double(totalBytes) * 100).rounded()))
}

func diskCounters() -> DiskCounters {
    var iterator: io_iterator_t = 0
    guard
        let matching = IOServiceMatching("IOBlockStorageDriver"),
        IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
    else {
        return DiskCounters()
    }
    defer { IOObjectRelease(iterator) }

    var counters = DiskCounters()
    var service = IOIteratorNext(iterator)
    while service != 0 {
        if
            let value = IORegistryEntryCreateCFProperty(
                service,
                "Statistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue(),
            let statistics = value as? [String: Any]
        {
            counters.read += (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            counters.write += (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        IOObjectRelease(service)
        service = IOIteratorNext(iterator)
    }
    return counters
}

func refreshInterval() -> Int {
    guard
        let flagIndex = CommandLine.arguments.firstIndex(of: "--interval"),
        CommandLine.arguments.indices.contains(flagIndex + 1),
        let value = Int(CommandLine.arguments[flagIndex + 1])
    else {
        return 1
    }
    return min(max(value, 1), 60)
}

func emit(
    networkSampler: ExternalNetworkSampler,
    previousNetworkSampleTime: inout TimeInterval,
    previousDisk: inout DiskCounters,
    previousDiskSampleTime: inout TimeInterval,
    previousCPU: inout CPUCounters
) {
    let sampledNetwork = networkSampler.takeCounters()
    let currentNetworkSampleTime = ProcessInfo.processInfo.systemUptime
    let networkSampleInterval = max(currentNetworkSampleTime - previousNetworkSampleTime, 0.001)
    let externalDownload = sampledNetwork.download
    let externalUpload = sampledNetwork.upload
    var interfaces: [String: [String: UInt64]] = [:]

    previousNetworkSampleTime = currentNetworkSampleTime
    interfaces["external"] = [
        "downloadBytesPerSecond": UInt64(Double(externalDownload) / networkSampleInterval),
        "uploadBytesPerSecond": UInt64(Double(externalUpload) / networkSampleInterval)
    ]
    let currentDisk = diskCounters()
    let currentDiskSampleTime = ProcessInfo.processInfo.systemUptime
    let diskSampleInterval = max(currentDiskSampleTime - previousDiskSampleTime, 0.001)
    let diskRead = currentDisk.read >= previousDisk.read
        ? currentDisk.read - previousDisk.read
        : 0
    let diskWrite = currentDisk.write >= previousDisk.write
        ? currentDisk.write - previousDisk.write
        : 0
    previousDisk = currentDisk
    previousDiskSampleTime = currentDiskSampleTime

    let currentCPU = cpuCounters()
    let activeDelta = currentCPU.active >= previousCPU.active
        ? currentCPU.active - previousCPU.active
        : 0
    let totalDelta = currentCPU.total >= previousCPU.total
        ? currentCPU.total - previousCPU.total
        : 0
    previousCPU = currentCPU
    let cpuUsage = totalDelta > 0
        ? min(100, UInt64((Double(activeDelta) / Double(totalDelta) * 100).rounded()))
        : 0

    let payload: [String: Any] = [
        "downloadBytesPerSecond": UInt64(Double(externalDownload) / networkSampleInterval),
        "uploadBytesPerSecond": UInt64(Double(externalUpload) / networkSampleInterval),
        "diskReadBytesPerSecond": UInt64(Double(diskRead) / diskSampleInterval),
        "diskWriteBytesPerSecond": UInt64(Double(diskWrite) / diskSampleInterval),
        "cpuUsagePercent": cpuUsage,
        "memoryUsagePercent": memoryUsagePercent(),
        "interfaces": interfaces
    ]

    guard
        let data = try? JSONSerialization.data(withJSONObject: payload),
        var line = String(data: data, encoding: .utf8)
    else {
        return
    }

    line.append("\n")
    FileHandle.standardOutput.write(Data(line.utf8))
}

_ = setpgid(0, 0)

let interval = refreshInterval()
let networkSampler: ExternalNetworkSampler
do {
    networkSampler = try ExternalNetworkSampler()
} catch {
    FileHandle.standardError.write(Data("Unable to start nettop: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
signal(SIGTERM, SIG_IGN)
let shutdownSignal = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
shutdownSignal.setEventHandler {
    networkSampler.stop()
    exit(EXIT_SUCCESS)
}
shutdownSignal.resume()
var previousNetworkSampleTime = ProcessInfo.processInfo.systemUptime
var previousDisk = diskCounters()
var previousDiskSampleTime = ProcessInfo.processInfo.systemUptime
var previousCPU = cpuCounters()

while true {
    Thread.sleep(forTimeInterval: TimeInterval(interval))
    autoreleasepool {
        emit(
            networkSampler: networkSampler,
            previousNetworkSampleTime: &previousNetworkSampleTime,
            previousDisk: &previousDisk,
            previousDiskSampleTime: &previousDiskSampleTime,
            previousCPU: &previousCPU
        )
    }
}

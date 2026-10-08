import Darwin
import Foundation

final class BenchmarkRunner {
  static let launchDuration = 10000
  static let startupDelay = 5000
  static let showDuration = 500
  static let hideDuration = 500
  static let shortcutIndex = 0
  private static var remainingCycles = 0
  private static var currentCycle = 0
  private static var startedAt = 0.0
  private static var didEmitStartup = false

  static func startIfNeeded() {
    startedAt = ProcessInfo.processInfo.systemUptime
    guard let config = BenchmarkConfig.parse(CommandLine.arguments) else { return }
    switch config.mode {
    case .launch:
      scheduleTerminate(after: launchDuration)
    case .showUi(let count):
      remainingCycles = count
      scheduleShow(after: startupDelay)
    }
  }

  private static func scheduleShow(after delay: Int) {
    guard remainingCycles > 0 else {
      scheduleTerminate(after: hideDuration)
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) {
      emitStartupIfNeeded()
      currentCycle += 1
      let started = ProcessInfo.processInfo.systemUptime
      App.showUi(shortcutIndex)
      emit("show", cycle: currentCycle, elapsedMs: milliseconds(since: started))
      scheduleHide(after: showDuration)
    }
  }

  private static func scheduleHide(after delay: Int) {
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) {
      let started = ProcessInfo.processInfo.systemUptime
      App.hideUi()
      emit("hide", cycle: currentCycle, elapsedMs: milliseconds(since: started))
      remainingCycles -= 1
      scheduleShow(after: hideDuration)
    }
  }

  private static func scheduleTerminate(after delay: Int) {
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) {
      emitStartupIfNeeded()
      emit("finish", cycle: 0, elapsedMs: milliseconds(since: startedAt))
      App.shared.terminate(nil)
    }
  }

  private static func emitStartupIfNeeded() {
    guard !didEmitStartup else { return }
    didEmitStartup = true
    emit("startup", cycle: 0, elapsedMs: milliseconds(since: startedAt))
  }

  private static func milliseconds(since start: Double) -> Double {
    (ProcessInfo.processInfo.systemUptime - start) * 1000
  }

  private static func emit(_ event: String, cycle: Int, elapsedMs: Double) {
    let memory = ProcessMemory.snapshot()
    let record = EventRecord(
      event: event,
      cycle: cycle,
      elapsedMs: (elapsedMs * 1000).rounded() / 1000,
      footprintBytes: memory.footprintBytes,
      peakFootprintBytes: memory.peakFootprintBytes,
      windowCount: Windows.list.count,
      applicationCount: Applications.list.count)
    guard let data = try? JSONEncoder().encode(record),
      let json = String(data: data, encoding: .utf8)
    else { return }
    print("ALTTAB_BENCHMARK \(json)")
    fflush(stdout)
  }

  private struct EventRecord: Encodable {
    let event: String
    let cycle: Int
    let elapsedMs: Double
    let footprintBytes: UInt64
    let peakFootprintBytes: UInt64
    let windowCount: Int
    let applicationCount: Int
  }
}

struct BenchmarkConfig {
  enum Mode {
    case launch
    case showUi(Int)
  }

  let mode: Mode

  static func parse(_ args: [String]) -> BenchmarkConfig? {
    guard let index = args.firstIndex(of: "--benchmark"), index + 1 < args.count else { return nil }
    let mode = args[index + 1]
    if mode == "launch" { return BenchmarkConfig(mode: .launch) }
    if mode == "showUi" { return parseShowUi(args, index) }
    print("Unsupported benchmark mode: \(mode)")
    return nil
  }

  private static func parseShowUi(_ args: [String], _ index: Int) -> BenchmarkConfig? {
    guard index + 2 < args.count, let count = Int(args[index + 2]), count > 0 else {
      print("Invalid benchmark showUi count")
      return nil
    }
    return BenchmarkConfig(mode: .showUi(count))
  }
}

private enum ProcessMemory {
  static func snapshot() -> (footprintBytes: UInt64, peakFootprintBytes: UInt64) {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
      }
    }
    guard kr == KERN_SUCCESS else { return (0, 0) }
    // SDK has phys_footprint; peak is ledger_phys_footprint_peak (no phys_footprint_peak field).
    let peak = info.ledger_phys_footprint_peak
    return (UInt64(info.phys_footprint), peak > 0 ? UInt64(peak) : 0)
  }
}

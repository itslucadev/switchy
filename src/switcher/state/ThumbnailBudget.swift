import Cocoa

/// Caps process-lifetime window-thumbnail byte counts. Count-capped at 20 and byte-capped
/// at 32 MiB, least-recently-used-evicted. The id just stored, and any id in `protecting`,
/// are never evicted, so a single newest thumbnail may exceed 32 MiB because it still has
/// to display. Tests construct a fresh instance; production uses `WindowThumbnails.thumbnailBudget`.
final class ThumbnailBudget {
    private static let maxCount = 20
    private static let maxBytes: UInt64 = 32 * 1024 * 1024
    private var sizes = [CGWindowID: UInt64]()
    private var lru = [CGWindowID]()  // most recently used last
    private var bytes: UInt64 = 0

    var totalBytes: UInt64 { bytes }
    var count: Int { lru.count }

    func contains(_ wid: CGWindowID) -> Bool { sizes[wid] != nil }

    func store(_ wid: CGWindowID, bytes: UInt64, protecting: Set<CGWindowID> = []) -> [CGWindowID] {
        if let old = sizes[wid] {
            subtract(old)
        }
        sizes[wid] = bytes
        add(bytes)
        lru.removeAll { $0 == wid }
        lru.append(wid)
        var keep = protecting
        keep.insert(wid)
        return evict(protecting: keep)
    }

    func forget(_ wid: CGWindowID) {
        guard let old = sizes.removeValue(forKey: wid) else { return }
        subtract(old)
        lru.removeAll { $0 == wid }
    }

    func touch(_ wid: CGWindowID) {
        guard sizes[wid] != nil else { return }
        lru.removeAll { $0 == wid }
        lru.append(wid)
    }

    func evict(protecting: Set<CGWindowID>) -> [CGWindowID] {
        var evicted = [CGWindowID]()
        while lru.count > 1 && (lru.count > Self.maxCount || bytes > Self.maxBytes) {
            guard let i = lru.firstIndex(where: { !protecting.contains($0) }) else { break }
            let victim = lru.remove(at: i)
            guard let size = sizes.removeValue(forKey: victim) else { continue }
            subtract(size)
            evicted.append(victim)
        }
        return evicted
    }

    private func add(_ n: UInt64) {
        let (sum, overflow) = bytes.addingReportingOverflow(n)
        bytes = overflow ? UInt64.max : sum
    }

    private func subtract(_ n: UInt64) {
        bytes = bytes < n ? 0 : bytes - n
    }
}

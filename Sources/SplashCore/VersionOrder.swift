import Foundation

/// Versions look like 0.28.2-alpha: three numbers, an optional suffix. Only the numbers decide which is newer.
public enum VersionOrder {
    static func numbers(_ version: String) -> [Int]? {
        let core = version.split(separator: "-").first.map(String.init) ?? version
        let parts = core.split(separator: ".").compactMap { Int($0) }
        return parts.count == 3 ? parts : nil
    }

    /// Whether `candidate` is a newer version than `current`. A build with no version ("dev") is older than every release.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let new = numbers(candidate) else { return false }
        guard let old = numbers(current) else { return true }
        return new != old && !new.lexicographicallyPrecedes(old)
    }
}

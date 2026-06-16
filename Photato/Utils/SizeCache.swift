import Foundation

enum SizeCache {
    private static let defaults = UserDefaults.standard

    static func load(_ key: String) -> String? {
        guard let size = defaults.object(forKey: "size_\(key)") as? Int else { return nil }
        return ByteFormatter.format(Int64(size))
    }

    static func save(_ key: String, size: Int64) {
        defaults.set(Int(size), forKey: "size_\(key)")
    }
}

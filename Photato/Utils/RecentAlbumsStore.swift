import Foundation

// MARK: - Recent Albums Store
/// 记录最近添加过照片的相簿 ID 列表（持久化在 UserDefaults）
/// 用于在「添加到相簿」面板中将最近添加过的相簿排在最前面
final class RecentAlbumsStore: @unchecked Sendable {
    static let shared = RecentAlbumsStore()
    private let userDefaultsKey = "photato_recent_added_album_ids"
    private let maxCount = 50
    private let lock = NSLock()

    private init() {}

    /// 最近添加过照片的相簿 localIdentifier 列表（越新越靠前）
    var recentAlbumIDs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return UserDefaults.standard.stringArray(forKey: userDefaultsKey) ?? []
    }

    /// 记录相簿被添加了素材（移至列表最前）
    func recordAlbumAdded(albumID: String) {
        guard !albumID.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var current = UserDefaults.standard.stringArray(forKey: userDefaultsKey) ?? []
        current.removeAll(where: { $0 == albumID })
        current.insert(albumID, at: 0)
        if current.count > maxCount {
            current = Array(current.prefix(maxCount))
        }
        UserDefaults.standard.set(current, forKey: userDefaultsKey)
    }
}

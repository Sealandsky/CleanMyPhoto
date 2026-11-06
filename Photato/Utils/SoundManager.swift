import Foundation
import AudioToolbox
import UIKit

/// 系统交互音效管理器：负责统一播放系统原生操作音效
/// - 点击操作按钮：acknowledgment_sent.m4a
/// - 列表页横滑删除照片：focus_change_app_icon.m4a
final class SoundManager: @unchecked Sendable {
    static let shared = SoundManager()

    enum SoundEffect: String, CaseIterable {
        case action = "acknowledgment_sent"
        case swipeDelete = "focus_change_app_icon"

        var fileName: String { rawValue }
        var fileExtension: String { "m4a" }
    }

    private var soundIDs: [String: SystemSoundID] = [:]
    private let lock = NSLock()

    private init() {
        preloadSounds()
    }

    deinit {
        lock.lock()
        for soundID in soundIDs.values {
            AudioServicesDisposeSystemSoundID(soundID)
        }
        soundIDs.removeAll()
        lock.unlock()
    }

    /// 预热/预加载所有音效，消除首次交互播放延迟
    func preloadSounds() {
        for effect in SoundEffect.allCases {
            _ = soundID(for: effect)
        }
    }

    /// 播放指定音效
    func play(_ effect: SoundEffect) {
        guard let id = soundID(for: effect) else { return }
        AudioServicesPlaySystemSound(id)
    }

    /// 点击操作按钮音效 (acknowledgment_sent.m4a)
    static func playAction() {
        shared.play(.action)
    }

    /// 列表页横滑删除照片音效 (focus_change_app_icon.m4a)
    static func playSwipeDelete() {
        shared.play(.swipeDelete)
    }

    // MARK: - Private Helpers

    private func soundID(for effect: SoundEffect) -> SystemSoundID? {
        lock.lock()
        defer { lock.unlock() }

        if let cachedID = soundIDs[effect.rawValue] {
            return cachedID
        }

        guard let soundURL = resolveSoundURL(name: effect.fileName, ext: effect.fileExtension) else {
            #if DEBUG
            print("[SoundManager] Warning: Sound file not found for \(effect.fileName).\(effect.fileExtension)")
            #endif
            return nil
        }

        var newSoundID: SystemSoundID = 0
        let status = AudioServicesCreateSystemSoundID(soundURL as CFURL, &newSoundID)
        if status == kAudioServicesNoError {
            soundIDs[effect.rawValue] = newSoundID
            return newSoundID
        } else {
            #if DEBUG
            print("[SoundManager] Error creating sound ID for \(effect.fileName): \(status)")
            #endif
            return nil
        }
    }

    private func resolveSoundURL(name: String, ext: String) -> URL? {
        // 1. 优先从 App Bundle 获取（支持 .m4a 和 .caf，支持 Sounds 子目录与根目录）
        if let bundleURL = Bundle.main.url(forResource: name, withExtension: ext) {
            return bundleURL
        }
        if let bundleSoundsURL = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Sounds") {
            return bundleSoundsURL
        }
        if let bundleCafURL = Bundle.main.url(forResource: name, withExtension: "caf") {
            return bundleCafURL
        }
        if let bundleSoundsCafURL = Bundle.main.url(forResource: name, withExtension: "caf", subdirectory: "Sounds") {
            return bundleSoundsCafURL
        }

        // 2. iOS 系统原生音效目录兜底（真机 /System/Library/Audio/UISounds/）
        let candidatePaths = [
            "/System/Library/Audio/UISounds/\(name).\(ext)",
            "/System/Library/Audio/UISounds/\(name).caf",
            "/System/Library/Audio/UISounds/Modern/\(name).\(ext)",
            "/System/Library/Audio/UISounds/Modern/\(name).caf",
            "/System/Library/Audio/UISounds/New/\(name).\(ext)",
            "/System/Library/Audio/UISounds/New/\(name).caf"
        ]

        for path in candidatePaths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }
}

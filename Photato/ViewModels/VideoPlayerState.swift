import SwiftUI
import Photos
import AVKit
import AVFoundation
import Combine
import UIKit

// MARK: - Video Player State
@MainActor
class VideoPlayerState: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var isMuted = true
    @Published var currentTime: TimeInterval = 0
    @Published var totalDuration: TimeInterval = 0
    /// 视频是否加载中：详情页左下角据此展示 loading，完成/失败自动移除
    @Published var isLoading = false

    /// 进度条拖动状态：拖动中仅更新 scrubProgress 驱动 UI 预览（时间标签与滑块位置），
    /// 不逐帧 seek（消除拖动卡顿）；松手 endScrub 时一次性跳转
    @Published var isScrubbing = false
    @Published var scrubProgress: Double = 0
    /// Seek 异步缓冲状态：松手后到 AVPlayer 实际跳转定位完成前为 true，
    /// 期间滑块与时间标签严格锁定在松手目标位置，防止被旧播放时间戳污染而弹跳
    @Published var isSeeking = false
    private var wasPlayingBeforeScrub = false
    private var seekToken = 0

    // 会话级静音记忆：仅存活于内存（static 属性随 @MainActor 类在主线程访问）。
    // App 全局默认视频音频为开启状态（sessionMuted = false）；
    // 用户手动关闭声音后，本次运行生命周期内后续视频保持静音；
    // 再次手动开启则跟随开启；App 重启后恢复默认开启声音（不落盘）。
    static var sessionMuted = false

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private(set) var currentAssetID: String?
    private var currentRequestID: PHImageRequestID?

    private func teardownCurrentPlayer() {
        if let observer = timeObserver, let player {
            player.removeTimeObserver(observer)
        }
        timeObserver = nil
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        endObserver = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    func loadVideo(for phAsset: PHAsset) {
        let assetID = phAsset.localIdentifier
        // 若当前已在播放该素材且播放器健康存活，坚决不重复请求，杜绝双播放器重叠发声
        guard currentAssetID != assetID || player == nil else { return }
        cleanup()
        currentAssetID = assetID
        isLoading = true

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        // 关键修复：指定为 highQualityFormat，强制 Photos 框架仅回调一次最终高质量视频资源，
        // 彻底杜绝 .automatic 模式下系统分两次下发（先代理资源、后高清资源）引发的双播放器并发重叠发声问题
        options.deliveryMode = .highQualityFormat

        let requestID = PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { [weak self] avAsset, _, info in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                // 若请求已被取消或当前已切到其他素材，直接丢弃晚到的旧请求
                if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled { return }
                guard strongSelf.currentAssetID == assetID else { return }

                // 幂等防护：若当前主线程已存在活跃播放器，丢弃重复生成
                if strongSelf.player != nil {
                    strongSelf.isLoading = false
                    return
                }

                if let avAsset {
                    strongSelf.teardownCurrentPlayer()

                    let item = AVPlayerItem(asset: avAsset)
                    let player = AVPlayer(playerItem: item)

                    let interval = CMTime(seconds: 0.1, preferredTimescale: 30)
                    // Inner closures weak-capture the outer weak self to avoid a retain
                    // cycle (self -> player -> observer closure -> self).
                    strongSelf.timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                        Task { @MainActor in
                            // 拖动中或松手 Seek 缓冲期间坚决丢弃旧的播放进度回调，杜绝滑块与时间标签跳动
                            guard let self = self, !self.isScrubbing, !self.isSeeking else { return }
                            self.currentTime = time.seconds
                            if let dur = player.currentItem?.duration, dur.isValid, !dur.isIndefinite {
                                self.totalDuration = dur.seconds
                            }
                        }
                    }

                    strongSelf.endObserver = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: item, queue: .main
                    ) { [weak self] _ in
                        Task { @MainActor in
                            item.seek(to: .zero, completionHandler: nil)
                            player.play()
                            self?.isPlaying = true
                        }
                    }

                    strongSelf.player = player
                    // 音频跟随会话级记忆（默认开启声音；用户手动静音过则保持静音）
                    let muted = Self.sessionMuted
                    player.isMuted = muted
                    strongSelf.isMuted = muted
                    // 视频进入可视区域即自动开始播放（滑动切换到下一个视频同样生效）
                    player.play()
                    strongSelf.isPlaying = true
                    strongSelf.isLoading = false
                } else {
                    // 加载失败：仅移除 loading，保留原有兜底 UI（底层静态首帧、无播放控件）
                    strongSelf.isLoading = false
                }
                strongSelf.currentRequestID = nil
            }
        }
        currentRequestID = requestID
    }

    /// App 切后台/失活时暂停播放（保留播放进度与声音记忆，不销毁播放器）
    func pausePlayback() {
        player?.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func toggleMute() {
        guard let player else { return }
        player.isMuted.toggle()
        isMuted = player.isMuted
        // 用户手动切换时记忆到会话级偏好，后续视频跟随（仅本次运行生命周期有效）
        Self.sessionMuted = isMuted
    }

    func seek(to progress: Double, completion: (() -> Void)? = nil) {
        guard let player, totalDuration > 0 else {
            completion?()
            return
        }
        let time = CMTime(seconds: progress * totalDuration, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            Task { @MainActor in
                completion?()
            }
        }
    }

    // MARK: - Scrub（拖动中保持 UI 预览，松手后执行 Seek 并加锁，零跳动平滑衔接）

    func beginScrub() {
        if !isScrubbing && !isSeeking {
            wasPlayingBeforeScrub = isPlaying
        }
        isSeeking = false
        isScrubbing = true
        // 拖动开始时暂停播放，避免后台持续推进播放时间引发音画错位与松手回跳
        player?.pause()
        isPlaying = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func updateScrub(_ progress: Double) {
        let clamped = min(max(progress, 0), 1)
        scrubProgress = clamped
        if totalDuration > 0 {
            currentTime = clamped * totalDuration
        }
    }

    func endScrub() {
        guard isScrubbing else { return }
        isScrubbing = false
        isSeeking = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if totalDuration > 0 {
            currentTime = scrubProgress * totalDuration
        }
        let targetProgress = scrubProgress
        seekToken += 1
        let currentToken = seekToken

        seek(to: targetProgress) { [weak self] in
            guard let self = self else { return }
            guard self.seekToken == currentToken else { return }
            // 若用户在 seek 完成前已开始新的拖拽，不打断新拖拽
            guard !self.isScrubbing else { return }
            self.isSeeking = false
            if self.wasPlayingBeforeScrub {
                self.player?.play()
                self.isPlaying = true
            }
        }
    }

    func cleanup() {
        if let reqID = currentRequestID {
            PHImageManager.default().cancelImageRequest(reqID)
            currentRequestID = nil
        }
        seekToken += 1
        isSeeking = false
        isScrubbing = false
        wasPlayingBeforeScrub = false
        teardownCurrentPlayer()
        currentAssetID = nil
        isPlaying = false
        currentTime = 0
        totalDuration = 0
        // 切换视频/退出详情页时立即隐藏 loading，避免残留；静音记忆（sessionMuted）跨视频保留，不在此复位
        isLoading = false
    }
}

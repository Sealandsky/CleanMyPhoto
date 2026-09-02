//
//  PHAsset+Image.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/2/7.
//

import SwiftUI
import Photos
import PhotosUI
import UIKit
import AVKit
import Combine

// MARK: - Image Memory Cache
@MainActor
final class PhotoImageCache {
    static let shared = PhotoImageCache()
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 100
    }

    func get(_ identifier: String) -> UIImage? {
        cache.object(forKey: identifier as NSString)
    }

    func set(_ identifier: String, image: UIImage) {
        cache.setObject(image, forKey: identifier as NSString)
    }
}

// MARK: - SwiftUI Image View for PHAsset
struct AssetImage: View {
    let asset: PHAsset
    let targetSize: CGSize
    let contentMode: ContentMode
    var highQuality: Bool = false
    var onLoad: (() -> Void)? = nil

    @State private var image: UIImage?
    /// 缩略图/高清均未就绪时为 true（展示 loading 指示器）
    @State private var isLoading = false

    init(asset: PHAsset, targetSize: CGSize, contentMode: ContentMode = .fit, highQuality: Bool = false, onLoad: (() -> Void)? = nil) {
        self.asset = asset
        self.targetSize = targetSize
        self.contentMode = contentMode
        self.highQuality = highQuality
        self.onLoad = onLoad
    }

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                // 缩略图与高清均未就绪：黑色兜底 + loading 指示器，
                // 不回退到其他图片
                ZStack {
                    Color.black
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                }
            }
        }
        .onAppear {
            if let cached = PhotoImageCache.shared.get(asset.localIdentifier) {
                image = cached
                onLoad?()
            }
            loadImage()
        }
        .onChange(of: asset.localIdentifier) { _, newID in
            // 切换图片：清掉属于旧照片的画面（禁止拿别的图片当占位），
            // 命中缓存则立即显示本图缩略，否则走「缩略图先行 → 高清替换」
            image = nil
            isLoading = true
            if let cached = PhotoImageCache.shared.get(newID) {
                image = cached
                onLoad?()
            }
            loadImage()
        }
    }

    private func loadImage() {
        guard asset.localIdentifier.contains("-") else {
            isLoading = false
            return
        }
        // 尚无任何可显示内容时展示 loading
        isLoading = (image == nil)

        // 缩略图先行：高清大图解码期间先用小图占位。
        // fastFormat 不写 PhotoImageCache，避免低清帧污染高清缓存；
        // image 非空（缓存/高清已到）时丢弃迟到的缩略图，防止画面回退
        if highQuality {
            let thumbnailOptions = PHImageRequestOptions()
            thumbnailOptions.deliveryMode = .fastFormat
            thumbnailOptions.isNetworkAccessAllowed = true
            thumbnailOptions.isSynchronous = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 600, height: 600),
                contentMode: .aspectFill,
                options: thumbnailOptions
            ) { [self] thumbnail, _ in
                Task { @MainActor in
                    if image == nil, let thumbnail {
                        image = thumbnail
                        onLoad?()
                    }
                }
            }
        }

        // 高清请求（原有逻辑）
        let options = PHImageRequestOptions()
        options.deliveryMode = highQuality ? .highQualityFormat : .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: self.targetSize,
            contentMode: .aspectFit,
            options: options
        ) { [self] resultImage, info in
            Task { @MainActor in
                if let img = resultImage {
                    self.image = img
                    PhotoImageCache.shared.set(self.asset.localIdentifier, image: img)
                    self.onLoad?()
                }
                // 成功或失败都结束 loading；失败时保持黑色兜底，不回退到其他图片
                self.isLoading = false

                if let error = info?[PHImageErrorKey] as? Error {
                    print("Image loading error: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Player UIView (AVPlayerLayer host)
final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    var player: AVPlayer? {
        didSet { playerLayer.player = player }
    }
}

// MARK: - Player Layer Bridge
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView()
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.player = player
    }

    static func dismantleUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.player = nil
    }
}

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

    // 会话级静音记忆：仅存活于内存（static 属性随 @MainActor 类在主线程访问）。
    // App 全局默认视频音频为开启状态（sessionMuted = false）；
    // 用户手动关闭声音后，本次运行生命周期内后续视频保持静音；
    // 再次手动开启则跟随开启；App 重启后恢复默认开启声音（不落盘）。
    static var sessionMuted = false

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var currentAssetID: String?

    func loadVideo(for phAsset: PHAsset) {
        let assetID = phAsset.localIdentifier
        guard currentAssetID != assetID else { return }
        cleanup()
        currentAssetID = assetID
        isLoading = true

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic

        PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { [weak self] avAsset, _, _ in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                // 快速切换视频时丢弃晚到的旧请求，防止旧播放器赋给新视频造成错乱
                guard strongSelf.currentAssetID == assetID else { return }

                if let avAsset {
                    let item = AVPlayerItem(asset: avAsset)
                    let player = AVPlayer(playerItem: item)

                    let interval = CMTime(seconds: 0.1, preferredTimescale: 30)
                    // Inner closures weak-capture the outer weak self to avoid a retain
                    // cycle (self -> player -> observer closure -> self).
                    strongSelf.timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                        Task { @MainActor in
                            self?.currentTime = time.seconds
                            if let dur = player.currentItem?.duration, dur.isValid, !dur.isIndefinite {
                                self?.totalDuration = dur.seconds
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
            }
        }
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

    func seek(to progress: Double) {
        guard let player, totalDuration > 0 else { return }
        let time = CMTime(seconds: progress * totalDuration, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func cleanup() {
        if let observer = timeObserver, let player {
            player.removeTimeObserver(observer)
        }
        timeObserver = nil
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        endObserver = nil
        currentAssetID = nil
        player?.pause()
        player = nil
        isPlaying = false
        currentTime = 0
        totalDuration = 0
        // 切换视频/退出详情页时立即隐藏 loading，避免残留；静音记忆（sessionMuted）跨视频保留，不在此复位
        isLoading = false
    }
}

// MARK: - Video Player View
struct VideoPlayerView: View {
    let asset: PHAsset
    var isDragging: Binding<Bool> = .constant(false)
    @StateObject private var state = VideoPlayerState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // 外层 ZStack 仅承载加载指示器（贴左下角），原有播放层结构不变
        ZStack(alignment: .bottomLeading) {
            ZStack {
                PlayerLayerView(player: state.player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if state.player != nil {
                    controlsOverlay
                        .opacity(isDragging.wrappedValue ? 0 : 1)
                        .animation(.easeInOut(duration: 0.2), value: isDragging.wrappedValue)
                }
            }

            // 视频加载中：左下角 loading，加载完成/失败由状态机自动移除
            if state.isLoading {
                ProgressView()
                    .tint(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(12)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.isLoading)
        .onAppear {
            state.loadVideo(for: asset)
        }
        .onChange(of: asset.localIdentifier) { _, _ in
            state.cleanup()
            state.loadVideo(for: asset)
        }
        .onDisappear {
            state.cleanup()
        }
        // App 切后台/失活时暂停播放（保留进度，声音记忆不变）；
        // 回到前台不自动恢复，由用户手动继续
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                state.pausePlayback()
            }
        }
    }

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            Spacer()

            HStack(spacing: 12) {
                Button {
                    state.togglePlayPause()
                } label: {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                }

                if state.totalDuration > 0 {
                    Text(formatTime(state.currentTime))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white)
                        .frame(width: 36, alignment: .trailing)

                    VideoScrubber(state: state)

                    Text(formatTime(state.totalDuration))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 36, alignment: .leading)
                }

                Spacer(minLength: 0)

                Button {
                    state.toggleMute()
                } label: {
                    Image(systemName: state.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 18, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let s = Int(max(0, time))
        if s < 3600 {
            return String(format: "%d:%02d", s / 60, s % 60)
        }
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}

// MARK: - Scrubber Width Preference Key
private struct ScrubberWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Video Scrubber
struct VideoScrubber: View {
    @ObservedObject var state: VideoPlayerState
    @State private var scrubberWidth: CGFloat = 0

    private var progress: Double {
        state.totalDuration > 0 ? min(max(state.currentTime / state.totalDuration, 0), 1) : 0
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(.white.opacity(0.3))
                .frame(height: 4)

            Rectangle()
                .fill(.white)
                .frame(width: scrubberWidth * progress, height: 4)

            Circle()
                .fill(.white)
                .frame(width: 16, height: 16)
                .offset(x: scrubberWidth * progress - 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 20)
        .contentShape(Rectangle())
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ScrubberWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(ScrubberWidthKey.self) { width in
            scrubberWidth = width
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard scrubberWidth > 0 else { return }
                    let p = max(0, min(1, value.location.x / scrubberWidth))
                    state.seek(to: p)
                }
        )
    }
}

// MARK: - Live Photo Player View
struct LivePhotoPlayerView: UIViewRepresentable {
    let asset: PHAsset

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .clear
        context.coordinator.loadLivePhoto(for: asset, into: view)
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        context.coordinator.loadLivePhoto(for: asset, into: uiView)
    }

    static func dismantleUIView(_ uiView: PHLivePhotoView, coordinator: Coordinator) {
        uiView.stopPlayback()
        uiView.livePhoto = nil
        coordinator.reset()
    }

    final class Coordinator {
        private var currentAssetID: String?

        func reset() { currentAssetID = nil }

        func loadLivePhoto(for phAsset: PHAsset, into view: PHLivePhotoView) {
            let assetID = phAsset.localIdentifier
            guard currentAssetID != assetID else { return }
            reset()
            currentAssetID = assetID

            let options = PHLivePhotoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestLivePhoto(for: phAsset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: options) { livePhoto, _ in
                guard let livePhoto else { return }
                Task { @MainActor in
                    view.livePhoto = livePhoto
                }
            }
        }
    }
}

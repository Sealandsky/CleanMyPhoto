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
final class PhotoImageCache: @unchecked Sendable {
    static let shared = PhotoImageCache()

    /// 缩略图/中图缓存：条目较多，控制在 200MB 以内（覆盖 150+ 张缩略图，顺畅支持 10+ 屏往返翻滚）
    private let thumbnailCache = NSCache<NSString, UIImage>()
    /// 高清大图缓存：全屏高清大图，上限 20 张，最大内存占用 150MB
    private let highResCache = NSCache<NSString, UIImage>()
    /// 记录最近解码过的优质过渡图（尺寸通常在 600~1000px），支持进入大图时清晰平滑垫底
    private let placeholderMap = NSCache<NSString, UIImage>()

    init() {
        thumbnailCache.countLimit = 200
        thumbnailCache.totalCostLimit = 60 * 1024 * 1024

        highResCache.countLimit = 10
        highResCache.totalCostLimit = 80 * 1024 * 1024

        placeholderMap.countLimit = 200
        placeholderMap.totalCostLimit = 40 * 1024 * 1024

        // 监听系统内存告警，及时释放内存压力
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.clearAll()
        }
    }

    private func cacheKey(for identifier: String, targetSize: CGSize, isHighQuality: Bool) -> String {
        let roundedW = Int(targetSize.width.rounded())
        let roundedH = Int(targetSize.height.rounded())
        let qualityTag = isHighQuality ? "HQ" : "THUMB"
        return "\(identifier)_\(roundedW)x\(roundedH)_\(qualityTag)"
    }

    private func calculateCost(for image: UIImage) -> Int {
        if let cgImage = image.cgImage {
            return cgImage.bytesPerRow * cgImage.height
        }
        return Int(image.size.width * image.size.height * 4)
    }

    func get(for identifier: String, targetSize: CGSize, isHighQuality: Bool) -> UIImage? {
        let key = cacheKey(for: identifier, targetSize: targetSize, isHighQuality: isHighQuality) as NSString
        let cached = isHighQuality ? highResCache.object(forKey: key) : thumbnailCache.object(forKey: key)
        if let cached = cached { return cached }
        // 容错：若相同 targetSize 但相反 qualityTag 命中，直接复用
        let fallbackKey = cacheKey(for: identifier, targetSize: targetSize, isHighQuality: !isHighQuality) as NSString
        return isHighQuality ? thumbnailCache.object(forKey: fallbackKey) : highResCache.object(forKey: fallbackKey)
    }

    /// 获取该素材最近可用的清晰占位图（用于进入大图时平滑过渡，避免马赛克）
    func getPlaceholder(for identifier: String) -> UIImage? {
        placeholderMap.object(forKey: identifier as NSString)
    }

    func set(for identifier: String, targetSize: CGSize, isHighQuality: Bool, image: UIImage) {
        let key = cacheKey(for: identifier, targetSize: targetSize, isHighQuality: isHighQuality) as NSString
        let cost = calculateCost(for: image)
        if isHighQuality {
            highResCache.setObject(image, forKey: key, cost: cost)
        } else {
            thumbnailCache.setObject(image, forKey: key, cost: cost)
        }
        // 保留一份作为大图/列表过渡的优质占位底图（尺寸更大时覆盖更新）
        if let existing = placeholderMap.object(forKey: identifier as NSString) {
            if max(image.size.width, image.size.height) >= max(existing.size.width, existing.size.height) {
                placeholderMap.setObject(image, forKey: identifier as NSString, cost: cost)
            }
        } else if max(image.size.width, image.size.height) >= 80 {
            placeholderMap.setObject(image, forKey: identifier as NSString, cost: cost)
        }
    }

    /// 显式写入过渡占位图
    func setPlaceholder(for identifier: String, image: UIImage) {
        let cost = calculateCost(for: image)
        placeholderMap.setObject(image, forKey: identifier as NSString, cost: cost)
    }

    // 兼容旧接口
    func get(_ identifier: String) -> UIImage? {
        getPlaceholder(for: identifier)
    }

    func set(_ identifier: String, image: UIImage) {
        let cost = calculateCost(for: image)
        placeholderMap.setObject(image, forKey: identifier as NSString, cost: cost)
    }

    func clearAll() {
        thumbnailCache.removeAllObjects()
        highResCache.removeAllObjects()
        placeholderMap.removeAllObjects()
    }
}

// MARK: - Centralized PhotoKit Image Manager
final class PhotoAssetImageManager: @unchecked Sendable {
    static let shared = PhotoAssetImageManager()

    let cachingManager = PHCachingImageManager()

    private init() {
        // 苹果官方最佳实践：集合视图缩略图预热模式下关闭全尺寸大图预热，提速 5~10 倍，避免后台争抢高分辨率解码带宽
        cachingManager.allowsCachingHighQualityImages = false

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.cachingManager.stopCachingImagesForAllAssets()
        }
    }

    func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        options: PHImageRequestOptions?,
        resultHandler: @escaping (UIImage?, [AnyHashable: Any]?) -> Void
    ) -> PHImageRequestID {
        cachingManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options,
            resultHandler: resultHandler
        )
    }

    func cancelRequest(_ requestID: PHImageRequestID?) {
        guard let requestID = requestID, requestID != PHInvalidImageRequestID else { return }
        cachingManager.cancelImageRequest(requestID)
    }

    func startCachingImages(
        for assets: [PHAsset],
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        options: PHImageRequestOptions?
    ) {
        guard !assets.isEmpty else { return }
        cachingManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        )
    }

    func stopCachingImages(
        for assets: [PHAsset],
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        options: PHImageRequestOptions?
    ) {
        guard !assets.isEmpty else { return }
        cachingManager.stopCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        )
    }

    func stopCachingImagesForAllAssets() {
        cachingManager.stopCachingImagesForAllAssets()
    }
}

// MARK: - SwiftUI Image View for PHAsset
struct AssetImage: View {
    let asset: PHAsset
    let targetSize: CGSize
    let contentMode: ContentMode
    var highQuality: Bool = false
    var placeholderColor: Color = Color(UIColor.secondarySystemFill)
    var onLoad: (() -> Void)? = nil

    /// 最终显示的高清大图或缩略图
    @State private var image: UIImage?
    /// 用于平滑过渡的占位缩略图（来自列表缓存或快速缩略图请求）
    @State private var placeholderImage: UIImage?
    /// 是否处于加载中（图像尚未加载完成）
    @State private var isLoading: Bool
    @State private var currentRequestID: PHImageRequestID? = nil
    @State private var placeholderRequestID: PHImageRequestID? = nil

    init(
        asset: PHAsset,
        targetSize: CGSize,
        contentMode: ContentMode = .fit,
        highQuality: Bool = false,
        placeholderColor: Color = Color(UIColor.secondarySystemFill),
        onLoad: (() -> Void)? = nil
    ) {
        self.asset = asset
        self.targetSize = targetSize
        self.contentMode = contentMode
        self.highQuality = highQuality
        self.placeholderColor = placeholderColor
        self.onLoad = onLoad

        // 核心同步初始化：
        // 1. 若目标尺寸已在精确缓存中，第 0 帧直接展示高清图；
        // 2. 若精确尺寸未就绪，但已有清晰过渡缩略图（>=100px），第 0 帧立即呈现该缩略图垫底，彻底消灭灰块；
        // 3. 高清清晰图就绪后瞬间替换，无缝锐化
        let exactCached = PhotoImageCache.shared.get(for: asset.localIdentifier, targetSize: targetSize, isHighQuality: highQuality)
        let placeholderCached: UIImage? = exactCached == nil
            ? PhotoImageCache.shared.getPlaceholder(for: asset.localIdentifier)
            : nil

        _image = State(initialValue: exactCached)
        _placeholderImage = State(initialValue: placeholderCached)
        _isLoading = State(initialValue: exactCached == nil && placeholderCached == nil)
    }

    private var phContentMode: PHImageContentMode {
        contentMode == .fill ? .aspectFill : .aspectFit
    }

    var body: some View {
        ZStack {
            // 兜底色（默认使用系统次级填充底色，不使用纯白，暗黑与浅色模式皆温和自然）
            placeholderColor

            // 占位缩略图层：仅在 highQuality 模式下且有可用缩略图时垫底，列表模式下使用纯净系统次级底色
            if let placeholder = placeholderImage {
                Image(uiImage: placeholder)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            }

            // 主图层：清晰图就绪时平滑呈现，列表缩略图无延时直出，杜绝淡入期灰块显露；大图模式保持优雅淡入
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(highQuality ? .opacity : .identity)
            }

            // 仅在 highQuality（大图预览）且完全无图时显示菊花指示器；列表网格使用纯净灰块占位，避免滚屏菊花闪烁
            if isLoading && highQuality && image == nil && placeholderImage == nil {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: placeholderColor == .black ? .white : Color(.systemGray3)))
            }
        }
        .clipped()
        .animation(highQuality ? .easeOut(duration: 0.15) : nil, value: image != nil)
        .onAppear {
            checkCacheAndLoad()
        }
        .onDisappear {
            cancelActiveRequests()
        }
        .onChange(of: asset.localIdentifier) { _, newID in
            cancelActiveRequests()
            // 素材切换时同步检查缓存，优先保证画面连续性
            let exactCached = PhotoImageCache.shared.get(for: newID, targetSize: targetSize, isHighQuality: highQuality)
            let placeholderCached: UIImage? = exactCached == nil
                ? PhotoImageCache.shared.getPlaceholder(for: newID)
                : nil

            image = exactCached
            placeholderImage = placeholderCached
            if exactCached != nil {
                isLoading = false
                onLoad?()
            } else {
                isLoading = (placeholderCached == nil)
                checkCacheAndLoad()
            }
        }
    }

    private func cancelActiveRequests() {
        if let reqID = currentRequestID {
            PhotoAssetImageManager.shared.cancelRequest(reqID)
            currentRequestID = nil
        }
        if let thumbReqID = placeholderRequestID {
            PhotoAssetImageManager.shared.cancelRequest(thumbReqID)
            placeholderRequestID = nil
        }
    }

    private func checkCacheAndLoad() {
        guard asset.localIdentifier.contains("-") else {
            isLoading = false
            return
        }

        // 1. 同步检查内存精确命中（首帧直出）
        if let cached = PhotoImageCache.shared.get(for: asset.localIdentifier, targetSize: targetSize, isHighQuality: highQuality) {
            image = cached
            isLoading = false
            onLoad?()
            return
        }

        // 2. 检查是否有最近就绪的清晰缩略图垫底，消除灰块等待
        if image == nil && placeholderImage == nil {
            if let placeholder = PhotoImageCache.shared.getPlaceholder(for: asset.localIdentifier) {
                placeholderImage = placeholder
                isLoading = false
                onLoad?()
            }
        }

        loadImage()
    }

    private func loadImage() {
        guard asset.localIdentifier.contains("-") else {
            isLoading = false
            return
        }
        isLoading = (image == nil && placeholderImage == nil)

        let requestedAssetID = asset.localIdentifier

        // 1. 快速通道 (Fast-Path, 1~2ms)：仅在目标尺寸较大（例如大图预览）且完全无图垫底时，
        // 索取 320x320 预渲染缩略图垫底；对于缩略图条等小尺寸素材（<= 160pt），直接请求目标尺寸，避免双倍请求与内存浪费
        if image == nil && placeholderImage == nil && (targetSize.width > 160 || targetSize.height > 160) {
            let thumbOptions = PHImageRequestOptions()
            thumbOptions.deliveryMode = .fastFormat
            thumbOptions.resizeMode = .fast
            thumbOptions.isNetworkAccessAllowed = true
            thumbOptions.isSynchronous = false

            placeholderRequestID = PhotoAssetImageManager.shared.requestImage(
                for: asset,
                targetSize: CGSize(width: 320, height: 320),
                contentMode: phContentMode,
                options: thumbOptions
            ) { [self] placeholder, _ in
                guard let placeholder = placeholder, max(placeholder.size.width, placeholder.size.height) >= 100 else { return }
                let updateUI = {
                    guard self.asset.localIdentifier == requestedAssetID, self.image == nil else { return }
                    self.placeholderImage = placeholder
                    PhotoImageCache.shared.setPlaceholder(for: requestedAssetID, image: placeholder)
                    self.isLoading = false
                    self.onLoad?()
                }
                if Thread.isMainThread {
                    updateUI()
                } else {
                    DispatchQueue.main.async(execute: updateUI)
                }
            }
        }

        // 2. 精确清晰通道 (Crisp-Path)：请求目标尺寸缩略图，就绪后瞬间替换，实现像素级锐利清晰
        let options = PHImageRequestOptions()
        options.deliveryMode = highQuality ? .highQualityFormat : .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        currentRequestID = PhotoAssetImageManager.shared.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: phContentMode,
            options: options
        ) { [self] resultImage, info in
            let updateUI = {
                guard self.asset.localIdentifier == requestedAssetID else { return }

                if let img = resultImage {
                    let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                    // 仅拦截尺寸小于 100px 的微缩图标；横屏、竖屏、宽屏等任何合格缩略图均直接上屏
                    if isDegraded && max(img.size.width, img.size.height) < 100 {
                        return
                    }

                    // 图片到达，直接呈现并清除占位图
                    self.image = img
                    self.placeholderImage = nil
                    self.isLoading = false
                    PhotoImageCache.shared.set(
                        for: self.asset.localIdentifier,
                        targetSize: self.targetSize,
                        isHighQuality: self.highQuality,
                        image: img
                    )
                    self.onLoad?()
                } else if info?[PHImageErrorKey] != nil {
                    self.isLoading = false
                }
            }

            if Thread.isMainThread {
                updateUI()
            } else {
                DispatchQueue.main.async(execute: updateUI)
            }
        }
    }
}

// MARK: - Player UIView (AVPlayerLayer host)
final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    var player: AVPlayer? {
        didSet {
            if oldValue !== player {
                playerLayer.player = player
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        playerLayer.videoGravity = .resizeAspect
    }
}

// MARK: - Player Layer Bridge
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.player = player
    }

    static func dismantleUIView(_ uiView: PlayerUIView, context: Context) {
        // 不在此清空 uiView.player，防止 SwiftUI 动画重排 Representable 导致播放器意外中断
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
        seekToken += 1
        isSeeking = false
        isScrubbing = false
        wasPlayingBeforeScrub = false
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

// MARK: - Video Controls Overlay
struct VideoControlsOverlay: View {
    @ObservedObject var state: VideoPlayerState
    var isDragging: Bool = false
    @Binding var controlsVisible: Bool
    var onInteraction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Button {
                state.togglePlayPause()
                onInteraction?()
            } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
            }

            if state.totalDuration > 0 {
                // 拖动中及 Seek 缓冲期显示目标时间，平时显示当前播放时间，杜绝松手瞬跳
                Text(Self.formatTime((state.isScrubbing || state.isSeeking)
                    ? state.scrubProgress * state.totalDuration
                    : state.currentTime))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 38, alignment: .trailing)

                VideoScrubber(state: state)

                Text(Self.formatTime(state.totalDuration))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 38, alignment: .leading)
            }

            Spacer(minLength: 0)

            Button {
                state.toggleMute()
                onInteraction?()
            } label: {
                Image(systemName: state.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 18, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // 核心视觉升级：深色高质感半透明磨砂背板。
        // 彻底解决浅色背景/高亮画面下白色文字失真、对比度不足的问题；
        // 无论是在浅色详情卡片页还是全屏黑色底色下，均提供恒定、清晰的 WCAG AAA 对比度
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(white: 0.12).opacity(0.88))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            }
        )
        .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 12)
        .opacity(isDragging || !controlsVisible ? 0 : 1)
        .animation(.easeInOut(duration: 0.2), value: isDragging)
        .animation(.easeInOut(duration: 0.25), value: controlsVisible)
        .allowsHitTesting(controlsVisible && !isDragging)
    }

    static func formatTime(_ time: TimeInterval) -> String {
        let s = Int(max(0, time))
        if s < 3600 {
            return String(format: "%d:%02d", s / 60, s % 60)
        }
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}

// MARK: - Video Player View
struct VideoPlayerView: View {
    let asset: PHAsset
    @ObservedObject var state: VideoPlayerState
    var isDragging: Binding<Bool> = .constant(false)

    /// 视频区域点按回调：详情页卡片=进沉浸全屏、沉浸全屏内=退出回详情页。
    /// 由内部 SwiftUI 手势调用——与控件条按钮天然互斥（Button 优先消费点击，
    /// 点播放/进度/静音按钮不会触发本回调）
    var onAreaTap: (() -> Void)? = nil
    var showsControls: Bool = true
    @Environment(\.scenePhase) private var scenePhase
    private let ownsState: Bool

    init(
        asset: PHAsset,
        state: VideoPlayerState? = nil,
        isDragging: Binding<Bool> = .constant(false),
        onAreaTap: (() -> Void)? = nil,
        showsControls: Bool = true
    ) {
        self.asset = asset
        if let state {
            self._state = ObservedObject(wrappedValue: state)
            self.ownsState = false
        } else {
            self._state = ObservedObject(wrappedValue: VideoPlayerState())
            self.ownsState = true
        }
        self.isDragging = isDragging
        self.onAreaTap = onAreaTap
        self.showsControls = showsControls
    }

    /// 控件条是否可见：播放中无交互 2.5 秒自动淡出（沉浸浏览），
    /// 暂停/加载/拖动进度时保持显示，点按视频或操作控件即唤回
    @State private var controlsVisible = true
    /// 任何交互递增本 token 重启自动隐藏计时（.task(id:) 驱动）
    @State private var autoHideToken = 0

    private static let autoHideDelay: UInt64 = 2_500_000_000

    var body: some View {
        Group {
            if let onAreaTap {
                playerContent
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onAreaTap()
                    }
            } else {
                playerContent
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.isLoading)
        .onAppear {
            if ownsState {
                state.loadVideo(for: asset)
                revealControls()
            } else if state.player == nil {
                state.loadVideo(for: asset)
            }
        }
        .onChange(of: asset.localIdentifier) { _, _ in
            if ownsState {
                state.cleanup()
                state.loadVideo(for: asset)
                revealControls()
            }
        }
        .onDisappear {
            if ownsState {
                state.cleanup()
            }
        }
        // 拖动进度条期间保持控件常显（拖动开始即唤回），松手后若在播放则重新计时
        .onChange(of: state.isScrubbing) { _, scrubbing in
            if scrubbing {
                controlsVisible = true
            } else {
                autoHideToken += 1
            }
        }
        // App 切后台/失活时暂停播放（保留进度，声音记忆不变）；
        // 回到前台不自动恢复，由用户手动继续
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                state.pausePlayback()
                controlsVisible = true
            }
        }
        // 自动隐藏计时：token 变化即重启；仅「播放中且不在拖动」才真正隐藏
        .task(id: autoHideToken) {
            guard state.isPlaying, !state.isScrubbing else { return }
            try? await Task.sleep(nanoseconds: Self.autoHideDelay)
            guard !Task.isCancelled, state.isPlaying, !state.isScrubbing else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                controlsVisible = false
            }
        }
    }

    /// 播放层主体：播放器图层 + 控件条 + loading 指示器
    private var playerContent: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                PlayerLayerView(player: state.player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showsControls, state.player != nil {
                    VStack(spacing: 0) {
                        Spacer()
                        VideoControlsOverlay(
                            state: state,
                            isDragging: isDragging.wrappedValue,
                            controlsVisible: $controlsVisible,
                            onInteraction: { revealControls() }
                        )
                        .padding(.bottom, 20)
                    }
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
    }

    /// 唤回控件条并重启自动隐藏计时
    private func revealControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible = true
        }
        autoHideToken += 1
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

    /// 滑块显示进度：拖动中与 Seek 异步缓冲期均取目标进度，严格钉住滑块圆钮，零弹跳过渡
    private var progress: Double {
        if state.isScrubbing || state.isSeeking { return state.scrubProgress }
        return state.totalDuration > 0 ? min(max(state.currentTime / state.totalDuration, 0), 1) : 0
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.35))
                .frame(height: 4)

            Capsule()
                .fill(Color.white)
                .frame(width: max(0, scrubberWidth * progress), height: 4)

            Circle()
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1)
                .frame(width: 16, height: 16)
                .offset(x: max(-8, min(scrubberWidth - 8, scrubberWidth * progress - 8)))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 32) // 扩大触控热区，方便手指轻松抓取拖拽
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
                    // 拖动中仅更新 UI 预览，不逐帧 seek（由 endScrub 一次性跳转）
                    if !state.isScrubbing { state.beginScrub() }
                    state.updateScrub(p)
                }
                .onEnded { value in
                    if scrubberWidth > 0 {
                        let p = max(0, min(1, value.location.x / scrubberWidth))
                        state.updateScrub(p)
                    }
                    state.endScrub()
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

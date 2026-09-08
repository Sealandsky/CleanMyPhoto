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

    /// 缩略图/中图缓存：条目较多，控制在 100MB 以内
    private let thumbnailCache = NSCache<NSString, UIImage>()
    /// 高清大图缓存：全屏高清大图，上限 20 张，最大内存占用 150MB
    private let highResCache = NSCache<NSString, UIImage>()
    /// 记录最近解码过的优质过渡图（尺寸通常在 600~1000px），支持进入大图时清晰平滑垫底
    private let placeholderMap = NSCache<NSString, UIImage>()

    init() {
        thumbnailCache.countLimit = 300
        thumbnailCache.totalCostLimit = 100 * 1024 * 1024

        highResCache.countLimit = 20
        highResCache.totalCostLimit = 150 * 1024 * 1024

        placeholderMap.countLimit = 150
        placeholderMap.totalCostLimit = 60 * 1024 * 1024

        // 监听系统内存告警，及时释放内存压力
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
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
        // 允许高分辨率图像预热缓存，使得全屏滑动浏览相邻照片时能够瞬间呈现清晰图像
        cachingManager.allowsCachingHighQualityImages = true

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
        // 1. 若目标尺寸已在精确缓存中，第 0 帧直接展示；
        // 2. 若未精确命中，同步取出已有任意缩略图/占位图垫底，第 0 毫秒即有图显示，绝不白闪
        let exactCached = PhotoImageCache.shared.get(for: asset.localIdentifier, targetSize: targetSize, isHighQuality: highQuality)
        let placeholderCached = (exactCached == nil)
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

            // 占位缩略图层：若已有列表/过渡缩略图，在最终图像到达前稳定垫底，在主图淡入过程中始终保留，杜绝漏出底色或闪白
            if let placeholder = placeholderImage {
                Image(uiImage: placeholder)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            }

            // 主图层：高清大图就绪时带有平滑淡入效果（0.18s），优雅无缝替换缩略图
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }

            // 无任何图可展示时的加载指示器
            if isLoading && image == nil && placeholderImage == nil {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: placeholderColor == .black ? .white : Color(.systemGray3)))
            }
        }
        .clipped()
        .animation(.easeOut(duration: 0.18), value: image != nil)
        .onAppear {
            checkCacheAndLoad()
        }
        .onDisappear {
            cancelActiveRequests()
        }
        .onChange(of: asset.localIdentifier) { _, newID in
            cancelActiveRequests()
            // 素材切换时同步检查缓存，优先保证画面连续性，不赋 nil 造成白屏跳动
            let exactCached = PhotoImageCache.shared.get(for: newID, targetSize: targetSize, isHighQuality: highQuality)
            let placeholderCached = (exactCached == nil)
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

        // 2. 未命中精确尺寸时，先展示已有任意缩略图垫底，绝无白屏或菊花
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

        // 高清模式过渡图：若当前完全没有任何画面垫底，先发轻量快速缩略图请求垫底
        if highQuality && image == nil && placeholderImage == nil {
            let thumbOptions = PHImageRequestOptions()
            thumbOptions.deliveryMode = .fastFormat
            thumbOptions.isNetworkAccessAllowed = true
            thumbOptions.isSynchronous = false

            let requestedAssetID = asset.localIdentifier
            placeholderRequestID = PhotoAssetImageManager.shared.requestImage(
                for: asset,
                targetSize: CGSize(width: 600, height: 600),
                contentMode: phContentMode,
                options: thumbOptions
            ) { [self] placeholder, _ in
                let updateUI = {
                    guard self.asset.localIdentifier == requestedAssetID else { return }
                    if self.image == nil, let placeholder = placeholder {
                        self.placeholderImage = placeholder
                        PhotoImageCache.shared.setPlaceholder(for: requestedAssetID, image: placeholder)
                        self.isLoading = false
                        self.onLoad?()
                    }
                }
                if Thread.isMainThread {
                    updateUI()
                } else {
                    DispatchQueue.main.async(execute: updateUI)
                }
            }
        }

        // 主请求：高清大图或列表缩略图
        let options = PHImageRequestOptions()
        options.deliveryMode = highQuality ? .highQualityFormat : .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        let requestedAssetID = asset.localIdentifier
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
                    if isDegraded {
                        // 如果是中间降级帧，作为平滑过渡占位图显示，不直接赋给最终 image
                        if self.image == nil {
                            self.placeholderImage = img
                            PhotoImageCache.shared.setPlaceholder(for: requestedAssetID, image: img)
                            self.isLoading = false
                        }
                    } else {
                        // 最终高清图到达，平滑淡入替换缩略图
                        self.image = img
                        self.isLoading = false
                        PhotoImageCache.shared.set(
                            for: self.asset.localIdentifier,
                            targetSize: self.targetSize,
                            isHighQuality: self.highQuality,
                            image: img
                        )
                        self.onLoad?()
                    }
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

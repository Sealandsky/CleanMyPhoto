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
                Color.black
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
            if let cached = PhotoImageCache.shared.get(newID) {
                image = cached
                onLoad?()
            }
            loadImage()
        }
    }

    private func loadImage() {
        guard asset.localIdentifier.contains("-") else { return }

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

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var currentAssetID: String?

    func loadVideo(for phAsset: PHAsset) {
        let assetID = phAsset.localIdentifier
        guard currentAssetID != assetID else { return }
        cleanup()
        currentAssetID = assetID

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic

        PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { [weak self] avAsset, _, _ in
            guard let avAsset, let strongSelf = self else { return }
            Task { @MainActor in
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
                player.isMuted = true
                strongSelf.isPlaying = false
            }
        }
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
    }
}

// MARK: - Video Player View
struct VideoPlayerView: View {
    let asset: PHAsset
    var isDragging: Binding<Bool> = .constant(false)
    @StateObject private var state = VideoPlayerState()

    var body: some View {
        ZStack {
            PlayerLayerView(player: state.player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if state.player != nil {
                controlsOverlay
                    .opacity(isDragging.wrappedValue ? 0 : 1)
                    .animation(.easeInOut(duration: 0.2), value: isDragging.wrappedValue)
            }
        }
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

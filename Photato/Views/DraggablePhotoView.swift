
import SwiftUI
import Photos
import UIKit

struct DraggablePhotoView: View {
    let photos: [PhotoAsset]
    var currentPhotoID: String
    let onPhotoChange: (String, Int) -> Void
    var onDelete: ((PhotoAsset) -> Void)?
    let onDismiss: () -> Void
    let screenSize: CGSize
    let photoSpacing: CGFloat = 20

    @State private var localIndex: Int
    @State private var offset: CGSize = .zero
    @State private var isDragging = false
    @State private var isNavigating = false
    @State private var navigationID: UInt = 0
    @State private var deleteID: UInt = 0
    @State private var hasTriggeredHaptic = false
    // 卡片样式配置（和你截图匹配）
    private let cardCornerRadius: CGFloat = 24
    private let cardPadding: CGFloat = 0 // 卡片和屏幕边缘的距离
    private let cardShadowRadius: CGFloat = 16
    private let cardShadowOpacity: CGFloat = 0.15
    private let dismissThreshold: CGFloat = 60
    private let deleteThreshold: CGFloat = 80

    private var safeIndex: Int {
        photos.isEmpty ? 0 : min(max(localIndex, 0), photos.count - 1)
    }

    private var currentPhoto: PhotoAsset { photos[safeIndex] }
    private var previousPhoto: PhotoAsset? { safeIndex > 0 ? photos[safeIndex - 1] : nil }
    private var nextPhoto: PhotoAsset? { safeIndex < photos.count - 1 ? photos[safeIndex + 1] : nil }

    init(photos: [PhotoAsset], currentPhotoID: String, onPhotoChange: @escaping (String, Int) -> Void, onDelete: ((PhotoAsset) -> Void)? = nil, onDismiss: @escaping () -> Void, screenSize: CGSize) {
        self.photos = photos
        self.currentPhotoID = currentPhotoID
        self.onPhotoChange = onPhotoChange
        self.onDelete = onDelete
        self.onDismiss = onDismiss
        self.screenSize = screenSize
        let idx = photos.firstIndex(where: { $0.id == currentPhotoID }) ?? 0
        _localIndex = State(initialValue: idx)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(.systemBackground)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .contentShape(Rectangle())
                    .ignoresSafeArea()

                // Previous photo (visible when swiping right)
                if let prev = previousPhoto {
                    photoCardLayer(prev)
                        .offset(x: -screenSize.width - photoSpacing + offset.width)
                        .zIndex(0)
                }

                // Current photo
                currentMediaCardLayer(currentPhoto)
                    .offset(x: offset.width, y: offset.height)
                    .zIndex(1)

                // Next photo (visible when swiping left)
                if let next = nextPhoto {
                    photoCardLayer(next)
                        .offset(x: screenSize.width + photoSpacing + offset.width)
                        .zIndex(0)
                }

                // Delete indicator
                if showDeleteIndicator && onDelete != nil {
                    VStack {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(16)
                            .background(Circle().fill(Color.red.opacity(0.8)))
                        Text(String(localized: "Move to Trash"))
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                    }
                    .transition(.opacity)
                    .opacity(offset.height < -deleteThreshold ? 1 : 0.5)
                    .zIndex(10)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        handleDragChanged(value)
                    }
                    .onEnded { value in
                        handleDragEnded(value)
                    }
            )
        }
        .onChange(of: currentPhotoID) { _, newID in
            if let idx = photos.firstIndex(where: { $0.id == newID }) {
                localIndex = idx
            }
        }
    }

    // MARK: - Photo Layer (swipe neighbors — always thumbnail)
    private func photoLayer(_ photoAsset: PhotoAsset) -> some View {
        AssetImage(asset: photoAsset.asset, targetSize: ScreenSizeHelper.screenPhysicalSize, contentMode: .fit, highQuality: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
    }

    // MARK: - Current Photo Layer (media-appropriate player)
    @ViewBuilder
    private func currentMediaLayer(_ photoAsset: PhotoAsset) -> some View {
        switch photoAsset.mediaType {
        case .video:
            ZStack {
                photoLayer(photoAsset)
                VideoPlayerView(asset: photoAsset.asset, isDragging: $isDragging)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            .id(photoAsset.id)
        case .livePhoto:
            ZStack {
                photoLayer(photoAsset)
                LivePhotoPlayerView(asset: photoAsset.asset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            .id(photoAsset.id)
        default:
            AssetImage(asset: photoAsset.asset, targetSize: ScreenSizeHelper.screenPhysicalSize, contentMode: .fit, highQuality: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        }
    }
    // MARK: - Photo Card Layer（带卡片样式的前后图）
        private func photoCardLayer(_ photoAsset: PhotoAsset) -> some View {
            AssetImage(asset: photoAsset.asset, targetSize: ScreenSizeHelper.screenPhysicalSize, contentMode: .fit, highQuality: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .cornerRadius(cardCornerRadius)
                .shadow(color: .black.opacity(cardShadowOpacity), radius: cardShadowRadius, x: 0, y: 4)
                .padding(cardPadding)
                .clipped()
        }

        // MARK: - Current Photo Card Layer（带卡片样式的当前图）
        @ViewBuilder
        private func currentMediaCardLayer(_ photoAsset: PhotoAsset) -> some View {
            switch photoAsset.mediaType {
            case .video:
                ZStack {
                    photoCardLayer(photoAsset)
                    VideoPlayerView(asset: photoAsset.asset, isDragging: $isDragging)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .cornerRadius(cardCornerRadius)
                        .padding(cardPadding)
                        .clipped()
                }
                .id(photoAsset.id)
            case .livePhoto:
                ZStack {
                    photoCardLayer(photoAsset)
                    LivePhotoPlayerView(asset: photoAsset.asset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .cornerRadius(cardCornerRadius)
                        .padding(cardPadding)
                        .clipped()
                }
                .id(photoAsset.id)
            default:
                AssetImage(asset: photoAsset.asset, targetSize: ScreenSizeHelper.screenPhysicalSize, contentMode: .fit, highQuality: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .cornerRadius(cardCornerRadius)
                    .shadow(color: .black.opacity(cardShadowOpacity), radius: cardShadowRadius, x: 0, y: 4)
                    .padding(cardPadding)
                    .clipped()
            }
        }
    // MARK: - Gesture Handlers
    @State private var showDeleteIndicator = false

    private func handleDragChanged(_ value: DragGesture.Value) {
        if isNavigating { return }

        isDragging = true
        let translation = value.translation

        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.85)) {
            if abs(translation.width) > abs(translation.height) {
                offset = CGSize(width: translation.width, height: 0)
                showDeleteIndicator = false
            } else if translation.height > 0 {
                offset = CGSize(width: 0, height: translation.height)
                showDeleteIndicator = false
            } else {
                offset = CGSize(width: 0, height: translation.height)
                showDeleteIndicator = abs(translation.height) > deleteThreshold
            }
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        if isNavigating { return }

        let horizontal = value.translation.width
        let vertical = value.translation.height
        let velocity = value.velocity.width

        // Swipe up to delete
        if vertical < -deleteThreshold && onDelete != nil {
            performDeleteAnimation()
            return
        }

        // Swipe down to dismiss
        if vertical > dismissThreshold {
            performDismissAnimation()
            return
        }

        // Horizontal navigation with velocity + distance
        if abs(horizontal) > abs(vertical) {
            let distanceThreshold = screenSize.width * 0.35
            let velocityThreshold: CGFloat = 500

            let shouldGoForward = horizontal < -distanceThreshold ||
                (horizontal < 0 && velocity < -velocityThreshold)
            let shouldGoBackward = horizontal > distanceThreshold ||
                (horizontal > 0 && velocity > velocityThreshold)

            if shouldGoForward && nextPhoto != nil {
                navigate(direction: .forward)
            } else if shouldGoBackward && previousPhoto != nil {
                navigate(direction: .backward)
            } else {
                resetPosition()
            }
        } else {
            resetPosition()
        }
    }

    // MARK: - Navigate (in-place, no view recreation)
    private enum SwipeDirection { case forward, backward }

    private func navigate(direction: SwipeDirection) {
        guard (direction == .forward && localIndex < photos.count - 1) ||
              (direction == .backward && localIndex > 0) else {
            resetPositionWithBounce()
            return
        }

        let currentNavID = navigationID + 1
        navigationID = currentNavID
        isNavigating = true
        let pageStep = screenSize.width + photoSpacing
        withAnimation(.spring(response: 0.35, dampingFraction: 0.95)) {
            offset = direction == .forward
                ? CGSize(width: -pageStep, height: 0)
                : CGSize(width: pageStep, height: 0)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard navigationID == currentNavID else { return }

            if direction == .forward {
                localIndex += 1
            } else {
                localIndex -= 1
            }
            onPhotoChange(currentPhoto.id, localIndex)

            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                offset = .zero
                isDragging = false
            }
            isNavigating = false
            hasTriggeredHaptic = false
        }
    }

    // MARK: - Dismiss Animation
    private func performDismissAnimation() {
        withAnimation(.easeOut(duration: 0.3)) {
            offset = CGSize(width: 0, height: screenSize.height)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                onDismiss()
            }
        }
    }

    // MARK: - Delete Animation
    private func performDeleteAnimation() {
        triggerConfirmHaptic()

        let currentDelID = deleteID + 1
        deleteID = currentDelID

        let photoToDelete = currentPhoto
        let nextPhotoRef = nextPhoto
        let prevPhotoRef = previousPhoto
        let hasMore = nextPhotoRef != nil || prevPhotoRef != nil

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            offset = CGSize(width: 0, height: -screenSize.height)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard deleteID == currentDelID else { return }

            onDelete?(photoToDelete)

            if hasMore {
                if let next = nextPhotoRef {
                    onPhotoChange(next.id, localIndex)
                } else if let prev = prevPhotoRef, localIndex > 0 {
                    localIndex -= 1
                    onPhotoChange(prev.id, localIndex)
                }
            } else {
                onDismiss()
            }

            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                offset = .zero
                isDragging = false
                showDeleteIndicator = false
            }
        }
    }

    // MARK: - Reset
    private func resetPosition() {
        hasTriggeredHaptic = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            offset = .zero
            isDragging = false
        }
    }

    private func resetPositionWithBounce() {
        hasTriggeredHaptic = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            offset = .zero
            isDragging = false
        }
    }

    private func resetPositionImmediate() {
        hasTriggeredHaptic = false
        offset = .zero
        isDragging = false
    }

    // MARK: - Haptic Feedback
    private func triggerHapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func triggerConfirmHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}

// MARK: - Preview
#Preview {
    DraggablePhotoView(
        photos: [],
        currentPhotoID: "",
        onPhotoChange: { _, _ in },
        onDismiss: {},
        screenSize: CGSize(width: 393, height: 852)
    )
}

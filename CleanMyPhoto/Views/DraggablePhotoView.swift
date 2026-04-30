//
//  DraggablePhotoView.swift
//  CleanMyPhoto
//
//  Created by 陈嘉华 on 2026/2/7.
//

import SwiftUI
import Photos
import UIKit

struct DraggablePhotoView: View {
    let photos: [PhotoAsset]
    var currentPhotoID: String
    let onPhotoChange: (String, Int) -> Void
    let onDismiss: () -> Void
    let screenSize: CGSize

    @State private var localIndex: Int
    @State private var offset: CGSize = .zero
    @State private var isDragging = false
    @State private var isNavigating = false
    @State private var navigationID: UInt = 0
    @State private var hasTriggeredHaptic = false

    private let dismissThreshold: CGFloat = 60

    private var safeIndex: Int {
        photos.isEmpty ? 0 : min(max(localIndex, 0), photos.count - 1)
    }

    private var currentPhoto: PhotoAsset { photos[safeIndex] }
    private var previousPhoto: PhotoAsset? { safeIndex > 0 ? photos[safeIndex - 1] : nil }
    private var nextPhoto: PhotoAsset? { safeIndex < photos.count - 1 ? photos[safeIndex + 1] : nil }

    init(photos: [PhotoAsset], currentPhotoID: String, onPhotoChange: @escaping (String, Int) -> Void, onDismiss: @escaping () -> Void, screenSize: CGSize) {
        self.photos = photos
        self.currentPhotoID = currentPhotoID
        self.onPhotoChange = onPhotoChange
        self.onDismiss = onDismiss
        self.screenSize = screenSize
        let idx = photos.firstIndex(where: { $0.id == currentPhotoID }) ?? 0
        _localIndex = State(initialValue: idx)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .contentShape(Rectangle())
                    .ignoresSafeArea()

                // Previous photo (visible when swiping right)
                if let prev = previousPhoto {
                    photoLayer(prev)
                        .offset(x: -screenSize.width + offset.width)
                        .zIndex(0)
                }

                // Current photo
                photoLayer(currentPhoto)
                    .offset(x: offset.width)
                    .zIndex(1)

                // Next photo (visible when swiping left)
                if let next = nextPhoto {
                    photoLayer(next)
                        .offset(x: screenSize.width + offset.width)
                        .zIndex(0)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
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

    // MARK: - Photo Layer
    private func photoLayer(_ photoAsset: PhotoAsset) -> some View {
        AssetImage(asset: photoAsset.asset, targetSize: ScreenSizeHelper.screenPhysicalSize, contentMode: .fit, highQuality: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Gesture Handlers
    private func handleDragChanged(_ value: DragGesture.Value) {
        if isNavigating {
            completePendingNavigation()
        }

        isDragging = true
        let translation = value.translation

        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.85)) {
            if abs(translation.width) > abs(translation.height) {
                offset = CGSize(width: translation.width, height: 0)
            } else {
                offset = CGSize(width: 0, height: translation.height)
            }
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        let horizontal = value.translation.width
        let vertical = value.translation.height
        let velocity = value.velocity.width

        // Vertical dismiss (swipe down)
        if abs(vertical) > abs(horizontal) && vertical > dismissThreshold {
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

    private func completePendingNavigation() {
        if offset.width < 0 && localIndex < photos.count - 1 {
            localIndex += 1
        } else if offset.width > 0 && localIndex > 0 {
            localIndex -= 1
        }
        onPhotoChange(currentPhoto.id, localIndex)
        isNavigating = false
    }

    private func navigate(direction: SwipeDirection) {
        guard (direction == .forward && localIndex < photos.count - 1) ||
              (direction == .backward && localIndex > 0) else {
            resetPositionWithBounce()
            return
        }

        let currentNavID = navigationID + 1
        navigationID = currentNavID
        isNavigating = true

        withAnimation(.spring(response: 0.35, dampingFraction: 0.95)) {
            offset = direction == .forward
                ? CGSize(width: -screenSize.width, height: 0)
                : CGSize(width: screenSize.width, height: 0)
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
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            offset = CGSize(width: 0, height: screenSize.height)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
            resetPositionImmediate()
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

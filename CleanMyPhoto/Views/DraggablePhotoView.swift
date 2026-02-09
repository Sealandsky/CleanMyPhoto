//
//  DraggablePhotoView.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/2/7.
//

import SwiftUI
import Photos

struct DraggablePhotoView: View {
    let photo: PhotoAsset
    let onDelete: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let screenSize: CGSize

    @State private var offset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0
    @State private var isDragging = false

    private let swipeThreshold: CGFloat = 80

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .contentShape(Rectangle())

                // Photo
                AssetImage(asset: photo.asset, targetSize: geometry.size, contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .opacity(opacity)
                    .onAppear {
                        print("📐 DraggablePhotoView - geometry.size: \(geometry.size)")
                    }

                // Instructions overlay
                if !isDragging && offset == .zero {
                    instructionsOverlay
                }

                // Delete indicator
                if offset.height < -swipeThreshold {
                    deleteIndicator
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
    }

    // MARK: - Instructions Overlay
    private var instructionsOverlay: some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up")
                    Text("Swipe up to delete")
                }
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.6))
                .foregroundColor(.white)
                .cornerRadius(15)

                HStack(spacing: 8) {
                    Image(systemName: "arrow.left")
                    Image(systemName: "arrow.down")
                    Text("Left/Down for older")
                }
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.6))
                .foregroundColor(.white)
                .cornerRadius(15)

                HStack(spacing: 8) {
                    Image(systemName: "arrow.right")
                    Text("Right for newer")
                }
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.6))
                .foregroundColor(.white)
                .cornerRadius(15)
            }
            .padding(.bottom, 60)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Delete Indicator
    private var deleteIndicator: some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill")
                    .font(.title)
                Text("Release to Delete")
                    .font(.headline)
            }
            .foregroundColor(.red)
            .padding()
            .background(Color.black.opacity(0.8))
            .cornerRadius(15)
            .padding(.top, 60)

            Spacer()
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    // MARK: - Gesture Handlers
    private func handleDragChanged(_ value: DragGesture.Value) {
        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8)) {
            isDragging = true
            offset = value.translation

            // 只在向上滑动时添加缩放效果（删除手势）
            if value.translation.height < 0 && abs(value.translation.height) > abs(value.translation.width) {
                let progress = abs(value.translation.height) / screenSize.height
                scale = 1.0 - (progress * 0.3)
                opacity = 1.0 - (progress * 0.5)
            } else {
                scale = 1.0
                opacity = 1.0
            }
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        let horizontal = value.translation.width
        let vertical = value.translation.height

        // 向上滑动超过阈值 → 删除
        if vertical < -swipeThreshold && abs(vertical) > abs(horizontal) {
            performDeleteAnimation()
        }
        // 向右滑动 → 看更新的照片
        else if horizontal > swipeThreshold {
            resetPosition()
            onPrevious()
        }
        // 向左滑动 → 看更旧的照片
        else if horizontal < -swipeThreshold {
            resetPosition()
            onNext()
        }
        // 向下滑动 → 看更旧的照片
        else if vertical > swipeThreshold && abs(vertical) > abs(horizontal) {
            resetPosition()
            onNext()
        }
        // 未达到阈值 → 复位
        else {
            resetPosition()
        }
    }

    // MARK: - Delete Animation
    private func performDeleteAnimation() {
        withAnimation(.easeOut(duration: 0.3)) {
            offset = CGSize(width: 0, height: -screenSize.height)
            scale = 0.5
            opacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDelete()
            resetPosition()
        }
    }

    // MARK: - Reset Position
    private func resetPosition() {
        withAnimation(.easeOut(duration: 0.25)) {
            offset = .zero
            scale = 1.0
            opacity = 1.0
            isDragging = false
        }
    }
}

// MARK: - Preview
#Preview {
    DraggablePhotoView(
        photo: PhotoAsset(asset: PHAsset()),
        onDelete: {},
        onNext: {},
        onPrevious: {},
        screenSize: CGSize(width: 393, height: 852)
    )
}

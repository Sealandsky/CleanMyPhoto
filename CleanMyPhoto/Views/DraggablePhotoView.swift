//
//  DraggablePhotoView.swift
//  CleanMyPhoto
//
//  Created by Claude on 2026/2/7.
//

import SwiftUI
import Photos
import UIKit

struct DraggablePhotoView: View {
    let photo: PhotoAsset
    let onDelete: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onDismiss: () -> Void
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
                AssetImage(asset: photo.asset, targetSize: ScreenSizeHelper.screenPhysicalSize, contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .opacity(opacity)
                    .onAppear {
                        print("📐 DraggablePhotoView - geometry.size: \(geometry.size), physicalSize: \(ScreenSizeHelper.screenPhysicalSize)")
                    }

                // Delete indicator
                if offset.height < -swipeThreshold {
                    deleteIndicator
                }

                // Dismiss indicator
                if offset.height > swipeThreshold {
                    dismissIndicator
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

    // MARK: - Delete Indicator
    private var deleteIndicator: some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill")
                    .font(.headline)
                Text("Release to Delete")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .padding()
            .background(Color.red.opacity(1))
            .cornerRadius(15)
            .padding(.top, 60)

            Spacer()
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    // MARK: - Dismiss Indicator
    private var dismissIndicator: some View {
        VStack {
            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "chevron.down")
                    .font(.headline)
                Text("Release to Close")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .padding()
            .background(Color.blue.opacity(0.8))
            .cornerRadius(15)
            .padding(.bottom, 60)
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    // MARK: - Gesture Handlers
    private func handleDragChanged(_ value: DragGesture.Value) {
        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8)) {
            isDragging = true
            offset = value.translation

            // 向上或向下滑动时添加缩放效果
            if abs(value.translation.height) > abs(value.translation.width) {
                let progress = abs(value.translation.height) / screenSize.height
                scale = 1.0 - (progress * 0.2)
                opacity = 1.0 - (progress * 0.3)
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
        else if horizontal > swipeThreshold && abs(horizontal) > abs(vertical) {
            resetPosition()
            onPrevious()
        }
        // 向左滑动 → 看更旧的照片
        else if horizontal < -swipeThreshold && abs(horizontal) > abs(vertical) {
            resetPosition()
            onNext()
        }
        // 向下滑动 → 退出全屏
        else if vertical > swipeThreshold && abs(vertical) > abs(horizontal) {
            performDismissAnimation()
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

    // MARK: - Dismiss Animation
    private func performDismissAnimation() {
        withAnimation(.easeOut(duration: 0.3)) {
            offset = CGSize(width: 0, height: screenSize.height)
            scale = 0.8
            opacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
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
        onDismiss: {},
        screenSize: CGSize(width: 393, height: 852)
    )
}

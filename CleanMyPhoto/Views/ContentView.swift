//
//  ContentView.swift
//  CleanMyPhoto
//
//  Created by 陈嘉华 on 2026/2/7.
//

import SwiftUI
import Photos

struct ContentView: View {
    @StateObject private var photoManager = PhotoManager()
    @State private var showTrash = false
    @State private var currentPhotoID: String? = nil
    @State private var navigationDirection: NavigationDirection = .forward
    @State private var isFullscreenMode = false
    @State private var scrollToPhotoID: String? = nil
    @AppStorage("hasShownGestureInstructions") private var hasShownGestureInstructions: Bool = false
    @State private var showGestureInstructions: Bool = false

    enum NavigationDirection {
        case forward, backward
    }

    enum ViewMode {
        case list, fullscreen
    }

    var body: some View {
        Group {
            if photoManager.authorizationStatus == .notDetermined {
                permissionView
            } else if photoManager.authorizationStatus == .authorized || photoManager.authorizationStatus == .limited {
                mainView
            } else {
                deniedView
            }
        }
        .task {
            if photoManager.authorizationStatus == .notDetermined {
                await photoManager.requestAuthorization()
            } else if photoManager.authorizationStatus == .authorized || photoManager.authorizationStatus == .limited {
                // 如果已经有权限，直接加载照片
                if photoManager.displayedPhotos.isEmpty {
                    await photoManager.fetchAllPhotos()
                }
            }
        }
        .sheet(isPresented: $showTrash) {
            TrashView(photoManager: photoManager)
        }
        .alert("Error", isPresented: .constant(photoManager.errorMessage != nil)) {
            Button("OK") {
                photoManager.errorMessage = nil
            }
        } message: {
            if let errorMessage = photoManager.errorMessage {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Permission View
    private var permissionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.stack")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            VStack(spacing: 12) {
                Text("Photo Access Required")
                    .font(.title)
                    .fontWeight(.bold)

                Text("CleanMyPhoto needs access to your photo library to help you organize and delete unwanted photos.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            ProgressView()
                .scaleEffect(1.2)
        }
        .padding()
    }

    // MARK: - Denied View
    private var deniedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 80))
                .foregroundColor(.orange)

            VStack(spacing: 12) {
                Text("Access Denied")
                    .font(.title)
                    .fontWeight(.bold)

                Text("To use CleanMyPhoto, please enable photo library access in Settings.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button("Open Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Main View
    private var mainView: some View {
        ZStack {
            if photoManager.isLoading {
                loadingView
            } else if photoManager.displayedPhotos.isEmpty && photoManager.hasLoadedOnce {
                emptyLibraryView
            } else if isFullscreenMode {
                photoBrowserView
            } else if photoManager.displayedPhotos.isEmpty {
                // 还没加载完，显示 loadingView
                loadingView
            } else {
                photoListView
            }

            // Trash button overlay (only in list mode)
            if !photoManager.displayedPhotos.isEmpty && !isFullscreenMode {
                VStack {
                    HStack {
                        Spacer()

                        trashButton
                    }
                    .padding()

                    Spacer()
                }
            }
        }
        .background(Color.black)
    }

    // MARK: - Photo List View
    private var photoListView: some View {
        PhotoListView(
            photoManager: photoManager,
            onPhotoSelect: { photo in
                currentPhotoID = photo.id
                scrollToPhotoID = nil  // 重置，因为不是从返回操作触发的
                withAnimation(.easeInOut(duration: 0.3)) {
                    isFullscreenMode = true
                }
            },
            scrollToPhotoID: scrollToPhotoID
        )
    }

    // MARK: - Photo Browser
    private var photoBrowserView: some View {
        ZStack {
            // Full-screen content
            Group {
                if let currentPhoto = photoManager.displayedPhotos.first(where: { $0.id == currentPhotoID }) {
                    DraggablePhotoView(
                        photo: currentPhoto,
                        onDelete: {
                            handlePhotoDeletion(currentPhoto)
                        },
                        onNext: {
                            navigationDirection = .forward
                            goToNextPhoto()
                        },
                        onPrevious: {
                            navigationDirection = .backward
                            goToPreviousPhoto()
                        },
                        onDismiss: {
                            scrollToPhotoID = currentPhotoID
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isFullscreenMode = false
                            }
                        },
                        screenSize: UIScreen.main.bounds.size
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(currentPhoto.id)
                    .transition(systemTransition)
                    .onAppear {
                        print("🖼️ Displaying photo: \(currentPhoto.id)")
                        // 预加载当前照片前后的图片
                        if let currentIndex = photoManager.displayedPhotos.firstIndex(where: { $0.id == currentPhoto.id }) {
                            photoManager.preloadAssets(photoIndex: currentIndex)
                        }
                        // 显示手势提示（如果还没显示过）
                        showGestureInstructionsIfNeeded()
                    }
                } else if photoManager.displayedPhotos.isEmpty {
                    emptyLibraryView
                } else {
                    // Fallback: should not happen
                    Text("No photo selected")
                        .foregroundColor(.white)
                }
            }
            .ignoresSafeArea()

            // Gesture instructions overlay
            if showGestureInstructions {
                gestureInstructionsOverlay
            }

            // Back button and trash button overlay (in safe area)
            VStack {
                HStack {
                    Button {
                        scrollToPhotoID = currentPhotoID  // 设置需要滚动到的照片 ID
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isFullscreenMode = false
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.8))
                            .clipShape(Circle())
                    }

                    Spacer()

                    // Trash button
                    trashButton
                }
                .padding()

                Spacer()
            }
        }
        .onAppear {
            initializeCurrentPhoto()
            print("🔍 CurrentPhotoID: \(currentPhotoID?.description ?? "nil")")
            print("🔍 Displayed photos count: \(photoManager.displayedPhotos.count)")
        }
    }

    // MARK: - System Transition
    private var systemTransition: AnyTransition {
        let insertion = AnyTransition.move(edge: navigationDirection == .forward ? .trailing : .leading)
            .combined(with: .opacity)
        let removal = AnyTransition.move(edge: navigationDirection == .forward ? .leading : .trailing)
            .combined(with: .opacity)

        return .asymmetric(insertion: insertion, removal: removal)
    }

    // MARK: - Navigation
    private func goToNextPhoto() {
        guard let currentIndex = photoManager.displayedPhotos.firstIndex(where: { $0.id == currentPhotoID }) else {
            return
        }

        let nextIndex = currentIndex + 1
        if nextIndex < photoManager.displayedPhotos.count {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentPhotoID = photoManager.displayedPhotos[nextIndex].id
            }
        }
    }

    private func goToPreviousPhoto() {
        guard let currentIndex = photoManager.displayedPhotos.firstIndex(where: { $0.id == currentPhotoID }) else {
            return
        }

        let previousIndex = currentIndex - 1
        if previousIndex >= 0 {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentPhotoID = photoManager.displayedPhotos[previousIndex].id
            }
        }
    }

    // MARK: - Photo Deletion Handler
    private func handlePhotoDeletion(_ photo: PhotoAsset) {
        // 存储删除前的索引位置
        let deletedIndex = photoManager.displayedPhotos.firstIndex(where: { $0.id == photo.id }) ?? 0

        // 执行删除（在动画前）
        photoManager.addToTrash(photo)

        // 使用动画平滑过渡
        withAnimation(.easeInOut(duration: 0.3)) {
            // 根据 new 数组状态更新 currentPhotoID
            if photoManager.displayedPhotos.isEmpty {
                currentPhotoID = nil
                isFullscreenMode = false
            } else {
                // 智能选择：尝试保持视觉位置
                let nextIndex = min(deletedIndex, photoManager.displayedPhotos.count - 1)
                currentPhotoID = photoManager.displayedPhotos[nextIndex].id
            }
        }
    }

    // MARK: - Initialize Current Photo
    private func initializeCurrentPhoto() {
        if currentPhotoID == nil, let firstPhoto = photoManager.displayedPhotos.first {
            currentPhotoID = firstPhoto.id
        }
    }

    // MARK: - Trash Button
    private var trashButton: some View {
        Button {
            showTrash = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "trash.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(.black.opacity(0.8))
                    .clipShape(Circle())

                if photoManager.trashCount > 0 {
                    Text("\(photoManager.trashCount)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.red)
                        .clipShape(Circle())
                        .offset(x: 5, y: -5)
                }
            }
        }
    }

    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text("Loading photos...")
                .font(.headline)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
    }

    // MARK: - Gesture Instructions Overlay
    private var gestureInstructionsOverlay: some View {
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
                    Text("Left for older")
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

                HStack(spacing: 8) {
                    Image(systemName: "arrow.down")
                    Text("Swipe down to close")
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
        .transition(.opacity)
        .onAppear {
            // 3秒后自动隐藏提示
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeOut(duration: 0.5)) {
                    showGestureInstructions = false
                    hasShownGestureInstructions = true
                }
            }
        }
    }

    // MARK: - Show Gesture Instructions If Needed
    private func showGestureInstructionsIfNeeded() {
        // 如果还没显示过提示，则显示
        if !hasShownGestureInstructions && !showGestureInstructions {
            withAnimation(.easeIn(duration: 0.3)) {
                showGestureInstructions = true
            }
        }
    }

    // MARK: - Empty Library View
    private var emptyLibraryView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Photos Found")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Text("Your photo library appears to be empty.")
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    ContentView()
}

//
//  ContentView.swift
//  CleanMyPhoto
//
//  Created by 陈嘉华 on 2026/2/7.
//

import SwiftUI
import Photos

// TODO: UIScreen.main is deprecated in iOS 26.0. Replace with view.window.windowScene.screen

enum MainTab: String, CaseIterable {
    case allPhotos
    case albums
    case timeline

    var localizedText: String {
        switch self {
        case .allPhotos:
            return String(localized: "所有照片")
        case .albums:
            return String(localized: "相簿")
        case .timeline:
            return String(localized: "日期")
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var membershipManager: MembershipManager

    @State private var showTrash = false
    @State private var currentPhotoID: String? = nil
    @State private var navigationDirection: NavigationDirection = .forward
    @State private var isFullscreenMode = false
    @State private var scrollToPhotoID: String? = nil
    @State private var showMembershipPaywall = false
    @AppStorage("hasShownGestureInstructions") private var hasShownGestureInstructions: Bool = false
    @State private var showGestureInstructions: Bool = false

    // 相簿相关状态
    @State private var selectedTab: MainTab = .allPhotos
    @State private var selectedAlbum: AlbumModel? = nil
    @State private var albumManager: AlbumManager?
    @State private var systemAlbumManager: SystemAlbumManager?
    @State private var selectedMonthAlbum: MonthAlbum? = nil

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
            // 检查试用期
            if membershipManager.isTrialExpired {
                showMembershipPaywall = true
            }

            if photoManager.authorizationStatus == .notDetermined {
                await photoManager.requestAuthorization()
            } else if photoManager.authorizationStatus == .authorized || photoManager.authorizationStatus == .limited {
                // 如果已经有权限，直接加载照片
                if photoManager.displayedPhotos.isEmpty {
                    await photoManager.fetchAllPhotos()
                }
            }

            // 初始化 AlbumManager
            if albumManager == nil {
                albumManager = AlbumManager(photoManager: photoManager)
            }

            // 初始化 SystemAlbumManager
            if systemAlbumManager == nil {
                systemAlbumManager = SystemAlbumManager()
            }
        }
        .sheet(isPresented: $showTrash) {
            TrashView(photoManager: photoManager)
        }
        .sheet(isPresented: $showMembershipPaywall) {
            MembershipView(isMandatory: true)
        }
        .alert(String(localized: "Error"), isPresented: .constant(photoManager.errorMessage != nil)) {
            Button(String(localized: "OK")) {
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
                Text(String(localized: "Photo Access Required"))
                    .font(.title)
                    .fontWeight(.bold)

                Text(String(localized: "CleanMyPhoto needs access to your photo library to help you organize and delete unwanted photos."))
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
                Text(String(localized: "Access Denied"))
                    .font(.title)
                    .fontWeight(.bold)

                Text(String(localized: "To use CleanMyPhoto, please enable photo library access in Settings."))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button(String(localized: "Open Settings")) {
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
            contentViews

            // 顶部按钮 overlay (only in list mode)
            if !photoManager.displayedPhotos.isEmpty && !isFullscreenMode {
                topButtonOverlay
            }

            // Trial warning banner (仅在试用期≤1天且非会员时显示)
            if !membershipManager.isPremiumMember &&
               membershipManager.membershipStatus.isTrialActive &&
               membershipManager.remainingTrialDays <= 1 {
                trialWarningBanner
            }
        }
        .background(Color.black)
    }

    // MARK: - Content Views
    private var contentViews: some View {
        VStack(spacing: 0) {
            // 分段控制器（仅在非全屏模式下显示）
            if !isFullscreenMode {
                topSegmentedControl
            }

            // 内容视图
            if isFullscreenMode {
                photoBrowserView
            } else if let album = selectedAlbum, let albumMgr = albumManager {
                // 相簿照片视图
                AlbumPhotoListView(
                    albumManager: albumMgr,
                    photoManager: photoManager,
                    album: album,
                    onPhotoSelect: { photo in
                        currentPhotoID = photo.id
                        scrollToPhotoID = nil
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isFullscreenMode = true
                        }
                    },
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedAlbum = nil
                        }
                    },
                    scrollToPhotoID: scrollToPhotoID
                )
            } else {
                // 根据 tab 显示不同视图
                switch selectedTab {
                case .allPhotos:
                    if photoManager.isLoading {
                        loadingView
                    } else if photoManager.displayedPhotos.isEmpty && photoManager.hasLoadedOnce {
                        emptyLibraryView
                    } else {
                        photoListView
                    }
                case .albums:
                    if let albumMgr = albumManager {
                        AlbumListView(albumManager: albumMgr) { album in
                            selectedAlbum = album
                            Task {
                                await albumMgr.fetchPhotos(in: album)
                            }
                        }
                    } else {
                        loadingView
                    }
                case .timeline:
                    if let monthAlbum = selectedMonthAlbum {
                        // 显示月份照片列表
                        SystemMonthPhotosView(
                            monthAlbum: monthAlbum,
                            photoManager: photoManager,
                            onPhotoSelect: { photo in
                                currentPhotoID = photo.id
                                scrollToPhotoID = nil
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isFullscreenMode = true
                                }
                            },
                            onBack: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    selectedMonthAlbum = nil
                                }
                            },
                            scrollToPhotoID: scrollToPhotoID
                        )
                    } else if let systemAlbumMgr = systemAlbumManager {
                        PhotoGroupView(
                            albumManager: systemAlbumMgr,
                            photoManager: photoManager,
                            onMonthSelect: { monthAlbum in
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    selectedMonthAlbum = monthAlbum
                                }
                            }
                        )
                    } else {
                        loadingView
                    }
                }
            }
        }
    }

    // MARK: - Top Segmented Control
    private var topSegmentedControl: some View {
        Picker("View Mode", selection: $selectedTab) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Text(tab.localizedText).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.95))
        .onChange(of: selectedTab) { oldValue, newValue in
            // 切换 tab 时清除相簿选择
            if newValue != .albums {
                withAnimation {
                    selectedAlbum = nil
                }
            }

            // 切换到相簿 tab 时加载相簿列表
            if newValue == .albums, let albumMgr = albumManager {
                Task {
                    await albumMgr.fetchUserAlbums()
                }
            }
        }
    }

    // MARK: - Top Button Overlay
    private var topButtonOverlay: some View {
        VStack {
            HStack {
                // 会员升级按钮
                if !membershipManager.isPremiumMember {
                    membershipButton
                }

                Spacer()

                // 回收站按钮
                trashButton
            }
            .padding()

            Spacer()
        }
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
                // 根据当前模式选择不同的照片列表
                let currentPhotos: [PhotoAsset] = {
                    if let monthAlbum = selectedMonthAlbum {
                        // 月份照片列表
                        if let fetchResult = monthAlbum.fetchResult {
                            return (0..<fetchResult.count).compactMap { index in
                                guard index < fetchResult.count else { return nil }
                                let asset = fetchResult.object(at: index)
                                return PhotoAsset(asset: asset)
                            }
                        } else {
                            return monthAlbum.assets.map { PhotoAsset(asset: $0) }
                        }
                    } else if let albumMgr = albumManager, selectedAlbum != nil {
                        return albumMgr.displayedAlbumPhotos
                    } else {
                        return photoManager.displayedPhotos
                    }
                }()

                if let currentPhoto = currentPhotos.first(where: { $0.id == currentPhotoID }) {
                    DraggablePhotoView(
                        photo: currentPhoto,
                        onDelete: {
                            handlePhotoDeletion(currentPhoto)
                        },
                        onNext: {
                            navigationDirection = .forward
                            goToNextPhotoInCurrentAlbum()
                        },
                        onPrevious: {
                            navigationDirection = .backward
                            goToPreviousPhotoInCurrentAlbum()
                        },
                        onDismiss: {
                            scrollToPhotoID = currentPhotoID
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isFullscreenMode = false
                            }
                        },
                        screenSize: {
                            #if compiler(>=6.0)
                            // TODO: Replace with view.window.windowScene.screen (iOS 26.0+)
                            #endif
                            return UIScreen.main.bounds.size
                        }()
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(currentPhoto.id)
                    .transition(systemTransition)
                    .onAppear {
                        print("🖼️ Displaying photo: \(currentPhoto.id)")
                        // 预加载当前照片前后的图片
                        if let currentIndex = currentPhotos.firstIndex(where: { $0.id == currentPhoto.id }) {
                            if selectedAlbum == nil {
                                photoManager.preloadAssets(photoIndex: currentIndex)
                            }
                        }
                        // 显示手势提示（如果还没显示过）
                        showGestureInstructionsIfNeeded()
                    }
                } else if currentPhotos.isEmpty {
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
            if currentPhotoID == nil {
                initializeCurrentPhoto()
            }
            let currentPhotos = selectedAlbum != nil ? albumManager?.displayedAlbumPhotos ?? [] : photoManager.displayedPhotos
            print("🔍 CurrentPhotoID: \(currentPhotoID?.description ?? "nil")")
            print("🔍 Displayed photos count: \(currentPhotos.count)")
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

    // MARK: - Navigation for Album Photos
    private func goToNextPhotoInCurrentAlbum() {
        let currentPhotos: [PhotoAsset] = {
            if let monthAlbum = selectedMonthAlbum {
                // 月份照片列表
                if let fetchResult = monthAlbum.fetchResult {
                    return (0..<fetchResult.count).compactMap { index in
                        guard index < fetchResult.count else { return nil }
                        let asset = fetchResult.object(at: index)
                        return PhotoAsset(asset: asset)
                    }
                } else {
                    return monthAlbum.assets.map { PhotoAsset(asset: $0) }
                }
            } else if let albumMgr = albumManager, selectedAlbum != nil {
                return albumMgr.displayedAlbumPhotos
            } else {
                return photoManager.displayedPhotos
            }
        }()

        guard let currentIndex = currentPhotos.firstIndex(where: { $0.id == currentPhotoID }) else {
            return
        }

        let nextIndex = currentIndex + 1
        if nextIndex < currentPhotos.count {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentPhotoID = currentPhotos[nextIndex].id
            }
        }
    }

    private func goToPreviousPhotoInCurrentAlbum() {
        let currentPhotos: [PhotoAsset] = {
            if let monthAlbum = selectedMonthAlbum {
                // 月份照片列表
                if let fetchResult = monthAlbum.fetchResult {
                    return (0..<fetchResult.count).compactMap { index in
                        guard index < fetchResult.count else { return nil }
                        let asset = fetchResult.object(at: index)
                        return PhotoAsset(asset: asset)
                    }
                } else {
                    return monthAlbum.assets.map { PhotoAsset(asset: $0) }
                }
            } else if let albumMgr = albumManager, selectedAlbum != nil {
                return albumMgr.displayedAlbumPhotos
            } else {
                return photoManager.displayedPhotos
            }
        }()

        guard let currentIndex = currentPhotos.firstIndex(where: { $0.id == currentPhotoID }) else {
            return
        }

        let previousIndex = currentIndex - 1
        if previousIndex >= 0 {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentPhotoID = currentPhotos[previousIndex].id
            }
        }
    }

    // MARK: - Photo Deletion Handler
    private func handlePhotoDeletion(_ photo: PhotoAsset) {
        // 确定当前照片列表
        let currentPhotos: [PhotoAsset] = {
            if let monthAlbum = selectedMonthAlbum {
                // 月份照片列表
                if let fetchResult = monthAlbum.fetchResult {
                    return (0..<fetchResult.count).compactMap { index in
                        guard index < fetchResult.count else { return nil }
                        let asset = fetchResult.object(at: index)
                        return PhotoAsset(asset: asset)
                    }
                } else {
                    return monthAlbum.assets.map { PhotoAsset(asset: $0) }
                }
            } else if let albumMgr = albumManager, selectedAlbum != nil {
                return albumMgr.displayedAlbumPhotos
            } else {
                return photoManager.displayedPhotos
            }
        }()

        // 存储删除前的索引位置
        guard let deletedIndex = currentPhotos.firstIndex(where: { $0.id == photo.id }) else {
            return
        }

        // 在删除前确定下一张要显示的照片ID
        let nextPhotoID: String?
        if currentPhotos.count <= 1 {
            // 只有这一张照片，删除后退出全屏
            nextPhotoID = nil
        } else if deletedIndex < currentPhotos.count - 1 {
            // 不是最后一张，显示下一张
            nextPhotoID = currentPhotos[deletedIndex + 1].id
        } else {
            // 是最后一张，显示前一张
            nextPhotoID = currentPhotos[deletedIndex - 1].id
        }

        // 执行删除（在动画前）
        photoManager.addToTrash(photo)

        // 使用动画平滑过渡
        withAnimation(.easeInOut(duration: 0.3)) {
            if let nextID = nextPhotoID {
                // 显示下一张照片
                currentPhotoID = nextID
            } else {
                // 没有照片了，退出全屏
                currentPhotoID = nil
                isFullscreenMode = false
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

    // MARK: - Membership Button
    private var membershipButton: some View {
        Button {
            showMembershipPaywall = true
        } label: {
            Image(systemName: "crown.fill")
                .font(.title2)
                .foregroundColor(.yellow)
                .padding(12)
                .background(.black.opacity(0.8))
                .clipShape(Circle())
        }
    }

    // MARK: - Trial Warning Banner
    private var trialWarningBanner: some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)

                Text(String(localized: "试用期还剩 \(membershipManager.remainingTrialDays) 天"))
                    .font(.system(size: 13))
                    .foregroundColor(.white)

                Spacer()

                Button(String(localized: "升级")) {
                    showMembershipPaywall = true
                }
                .font(.system(size: 13))
                .foregroundColor(.blue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.orange.opacity(0.2))
            .cornerRadius(12)
            .padding(.horizontal, 16)

            Spacer()
        }
    }

    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text(String(localized: "Loading photos..."))
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
                    Text(String(localized: "Swipe up to delete"))
                }
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.6))
                .foregroundColor(.white)
                .cornerRadius(15)

                HStack(spacing: 8) {
                    Image(systemName: "arrow.left")
                    Text(String(localized: "Left for older"))
                }
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.6))
                .foregroundColor(.white)
                .cornerRadius(15)

                HStack(spacing: 8) {
                    Image(systemName: "arrow.right")
                    Text(String(localized: "Right for newer"))
                }
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.6))
                .foregroundColor(.white)
                .cornerRadius(15)

                HStack(spacing: 8) {
                    Image(systemName: "arrow.down")
                    Text(String(localized: "Swipe down to close"))
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

            Text(String(localized: "No Photos Found"))
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Text(String(localized: "Your photo library appears to be empty."))
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    ContentView()
}

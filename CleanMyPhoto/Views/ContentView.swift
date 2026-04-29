//
//  ContentView.swift
//  CleanMyPhoto
//
//  Created by 陈嘉华 on 2026/2/7.
//

import SwiftUI
import Photos

enum MainTab: String, CaseIterable {
    case allPhotos
    case albums
    case timeline

    var localizedText: String {
        switch self {
        case .allPhotos:
            return String(localized: "Library")
        case .albums:
            return String(localized: "Albums")
        case .timeline:
            return String(localized: "Timeline")
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

    // 导航路径
    @State private var albumsPath = NavigationPath()
    @State private var timelinePath = NavigationPath()

    // 滚动偏移状态
    @State private var scrollOffset: CGFloat = 0

    enum NavigationDirection {
        case forward, backward
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
                if photoManager.displayedPhotos.isEmpty {
                    await photoManager.fetchAllPhotos()
                }
            }

            if albumManager == nil {
                albumManager = AlbumManager(photoManager: photoManager)
            }

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

                Text(String(localized: "CleanMyPhoto needs access to your photo library to help you organize and clean up unwanted photos."))
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
        Group {
            // 内容视图
            if isFullscreenMode {
                photoBrowserView
            } else if selectedTab == .allPhotos {
                libraryNavigationView
            } else if selectedTab == .albums {
                albumsNavigationView
            } else if selectedTab == .timeline {
                timelineNavigationView
            }
        }
    }

    // MARK: - Library Navigation
    private var libraryNavigationView: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topSegmentedControl
                photoListView
            }
            .navigationTitle(appTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if !membershipManager.isPremiumMember {
                            membershipButton
                        }
                        trashButton
                    }
                }
            }
        }
        .tint(.white)
    }

    // MARK: - Navigation State
    private var isAtRootLevel: Bool {
        switch selectedTab {
        case .allPhotos:
            return true
        case .albums:
            return albumsPath.isEmpty
        case .timeline:
            return timelinePath.isEmpty
        }
    }

    // MARK: - App Title
    private var appTitle: String {
        switch selectedTab {
        case .allPhotos:
            return String(localized: "Library")
        case .albums:
            return String(localized: "Albums")
        case .timeline:
            return String(localized: "Timeline")
        }
    }

    // MARK: - Albums Navigation
    private var albumsNavigationView: some View {
        NavigationStack(path: $albumsPath) {
            VStack(spacing: 0) {
                topSegmentedControl
                Group {
                    if let albumMgr = albumManager {
                        AlbumListView(albumManager: albumMgr) { album in
                            selectedAlbum = album
                            Task { [album] in
                                await albumMgr.fetchPhotos(in: album)
                                guard selectedAlbum?.id == album.id else { return }
                                albumsPath.append(AlbumsDestination.albumPhotos(album.id))
                            }
                        }
                    } else {
                        loadingView
                    }
                }
            }
            .navigationTitle(appTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if !membershipManager.isPremiumMember {
                            membershipButton
                        }
                        trashButton
                    }
                }
            }
            .task {
                if let albumMgr = albumManager, albumMgr.albums.isEmpty {
                    await albumMgr.fetchUserAlbums()
                }
            }
            .navigationDestination(for: AlbumsDestination.self) { destination in
                switch destination {
                case .albumPhotos(let albumId):
                    if let album = albumManager?.albums.first(where: { $0.id == albumId }),
                       let albumMgr = albumManager {
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
                            scrollToPhotoID: scrollToPhotoID
                        )
                    }
                }
            }
        }
        .onChange(of: albumsPath) { oldValue, newValue in
            if newValue.isEmpty {
                selectedAlbum = nil
            }
        }
        .tint(.white)
    }

    // MARK: - Timeline Navigation
    private var timelineNavigationView: some View {
        NavigationStack(path: $timelinePath) {
            VStack(spacing: 0) {
                topSegmentedControl
                Group {
                    if let systemAlbumMgr = systemAlbumManager {
                        PhotoGroupView(
                            albumManager: systemAlbumMgr,
                            photoManager: photoManager,
                            onMonthSelect: { monthAlbum in
                                selectedMonthAlbum = monthAlbum
                                timelinePath.append(TimelineDestination.monthPhotos(monthAlbum.id))
                            }
                        )
                    } else {
                        loadingView
                    }
                }
            }
            .navigationTitle(appTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if !membershipManager.isPremiumMember {
                            membershipButton
                        }
                        trashButton
                    }
                }
            }
            .navigationDestination(for: TimelineDestination.self) { destination in
                switch destination {
                case .monthPhotos(let albumId):
                    if let monthAlbum = systemAlbumManager?.monthAlbums.first(where: { $0.id == albumId }) {
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
                            scrollToPhotoID: scrollToPhotoID
                        )
                    }
                }
            }
        }
        .onChange(of: timelinePath) { oldValue, newValue in
            if newValue.isEmpty {
                selectedMonthAlbum = nil
            }
        }
        .tint(.white)
    }

    // MARK: - Top Segmented Control
    private var topSegmentedControl: some View {
        Picker("View Mode", selection: $selectedTab) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Text(tab.localizedText)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.95))
        .onChange(of: selectedTab) { oldValue, newValue in
            scrollOffset = 0
            scrollToPhotoID = nil
            isFullscreenMode = false
            currentPhotoID = nil

            // 切换 tab 时清除导航路径
            albumsPath = NavigationPath()
            timelinePath = NavigationPath()
            selectedAlbum = nil
            selectedMonthAlbum = nil

            // 切换到相簿 tab 时加载相簿列表（仅首次）
            if newValue == .albums, let albumMgr = albumManager, albumMgr.albums.isEmpty {
                albumMgr.isLoadingAlbums = true
                Task {
                    await albumMgr.fetchUserAlbums()
                }
            }
        }
    }

    // MARK: - Photo List View
    private var photoListView: some View {
        PhotoListView(
            photoManager: photoManager,
            onPhotoSelect: { photo in
                currentPhotoID = photo.id
                scrollToPhotoID = nil
                withAnimation(.easeInOut(duration: 0.3)) {
                    isFullscreenMode = true
                }
            },
            scrollToPhotoID: scrollToPhotoID,
            onScrollOffsetChanged: { offset in
                scrollOffset = offset
            }
        )
    }

    // MARK: - Photo Browser
    private var photoBrowserView: some View {
        ZStack {
            Group {
                let currentPhotos: [PhotoAsset] = {
                    if let monthAlbum = selectedMonthAlbum {
                        return monthAlbum.photoAssets
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
                        screenSize: ScreenSizeHelper.screenSize
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(currentPhoto.id)
                    .transition(systemTransition)
                    .onAppear {
                        if let currentIndex = currentPhotos.firstIndex(where: { $0.id == currentPhoto.id }) {
                            if selectedAlbum == nil {
                                photoManager.preloadAssets(photoIndex: currentIndex)
                            }
                        }
                        showGestureInstructionsIfNeeded()
                    }
                } else if currentPhotos.isEmpty {
                    emptyLibraryView
                } else {
                    Text("No photo selected")
                        .foregroundColor(.white)
                }
            }
            .ignoresSafeArea()

            if showGestureInstructions {
                gestureInstructionsOverlay
            }

            VStack {
                HStack {
                    Button {
                        scrollToPhotoID = currentPhotoID
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isFullscreenMode = false
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body)
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.glass)

                    Spacer()

                    trashButton
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Spacer()
            }
        }
        .onAppear {
            let currentPhotos: [PhotoAsset] = {
                if let monthAlbum = selectedMonthAlbum {
                    return monthAlbum.photoAssets
                } else if let albumMgr = albumManager, selectedAlbum != nil {
                    return albumMgr.displayedAlbumPhotos
                } else {
                    return photoManager.displayedPhotos
                }
            }()

            if let id = currentPhotoID, !currentPhotos.isEmpty {
                if !currentPhotos.contains(where: { $0.id == id }) {
                    currentPhotoID = currentPhotos.first?.id
                }
            } else if currentPhotoID == nil {
                initializeCurrentPhoto()
            }
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

    // MARK: - Navigation for Album Photos
    private func goToNextPhotoInCurrentAlbum() {
        let currentPhotos: [PhotoAsset] = {
            if let monthAlbum = selectedMonthAlbum {
                return monthAlbum.photoAssets
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
                return monthAlbum.photoAssets
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
        guard !membershipManager.isTrialExpired || membershipManager.isPremiumMember else {
            showMembershipPaywall = true
            return
        }

        let currentPhotos: [PhotoAsset] = {
            if let monthAlbum = selectedMonthAlbum {
                return monthAlbum.photoAssets
            } else if let albumMgr = albumManager, selectedAlbum != nil {
                return albumMgr.displayedAlbumPhotos
            } else {
                return photoManager.displayedPhotos
            }
        }()

        guard let deletedIndex = currentPhotos.firstIndex(where: { $0.id == photo.id }) else {
            return
        }

        let nextPhotoID: String?
        if currentPhotos.count <= 1 {
            nextPhotoID = nil
        } else if deletedIndex < currentPhotos.count - 1 {
            nextPhotoID = currentPhotos[deletedIndex + 1].id
        } else {
            nextPhotoID = currentPhotos[deletedIndex - 1].id
        }

        photoManager.addToTrash(photo)

        withAnimation(.easeInOut(duration: 0.3)) {
            if let nextID = nextPhotoID {
                currentPhotoID = nextID
            } else {
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
                    .font(.body)
                    .foregroundColor(.white)

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
            .frame(width: 36, height: 40)
            .clipShape(Circle())
        }
        .buttonStyle(.glass)
    }

    // MARK: - Membership Button
    private var membershipButton: some View {
        Button {
            showMembershipPaywall = true
        } label: {
            Image(systemName: "crown.fill")
                .font(.body)
                .foregroundColor(.yellow)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.glass)
    }

    // MARK: - Trial Warning Banner
    private var trialWarningBanner: some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)

                Text(String(localized: "Trial expires in \(membershipManager.remainingTrialDays) days"))
                    .font(.system(size: 13))
                    .foregroundColor(.white)

                Spacer()

                Button(String(localized: "Upgrade")) {
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

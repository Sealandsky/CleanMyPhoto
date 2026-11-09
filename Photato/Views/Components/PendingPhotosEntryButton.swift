import SwiftUI
import Photos

// MARK: - Pending Photos Entry Button (待处理照片入口按钮)
/// 右上角通用待处理入口：
/// 1. 空态：38×38pt（44×44 触控区）圆形胶囊 + 原生 trash 图标；
/// 2. 非空态：自适应 Liquid Glass 胶囊 + 双张倾斜正方形相纸微缩堆叠 + 数字；
/// 3. 新增照片实时顶替入场，清空时平滑恢复。
struct PendingPhotosEntryButton: View {
    @EnvironmentObject var photoManager: PhotoManager
    var isLiquidGlass: Bool = false

    var body: some View {
        if isLiquidGlass {
            Button {
                photoManager.showTrash = true
            } label: {
                buttonContent
                    .foregroundColor(.primary)
                    .padding(.horizontal, photoManager.trashCount > 0 ? 12 : 0)
                    .frame(minWidth: 44, minHeight: 44)
                    .frame(width: photoManager.trashCount > 0 ? nil : 44, height: 44)
                    .modifier(HeaderLiquidGlassModifier())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            // VoiceOver：读出“待处理照片”，有数量时一并读出
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Pending Photos"))
        } else {
            Button {
                photoManager.showTrash = true
            } label: {
                buttonContent
                    .foregroundColor(.primary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Pending Photos"))
        }
    }

    private var buttonContent: some View {
        HStack(spacing: 5) {
            if photoManager.trashCount == 0 {
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .transition(.scale.combined(with: .opacity))
            } else {
                TrashPhotoStackIcon(recentPhotos: Array(photoManager.trashedAssets.suffix(2)))
                    .transition(.scale.combined(with: .opacity))
            }

            if photoManager.trashCount > 0 {
                Text("\(photoManager.trashCount)")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: photoManager.trashCount)
    }
}

// MARK: - Trash Photo Stack Icon (双张倾斜正方形相纸堆叠)
struct TrashPhotoStackIcon: View {
    let recentPhotos: [PhotoAsset]

    var body: some View {
        ZStack {
            if recentPhotos.count >= 2 {
                // 底层照片（第二新）
                ThumbnailPolaroidCard(photo: recentPhotos[recentPhotos.count - 2])
                    .rotationEffect(.degrees(-8.5))
                    .offset(x: -1.5, y: 1.0)
                    .zIndex(1)
            }

            if let latest = recentPhotos.last {
                // 顶层照片（最新加入）
                ThumbnailPolaroidCard(photo: latest)
                    .rotationEffect(.degrees(recentPhotos.count == 1 ? -3.5 : 6.5))
                    .offset(x: recentPhotos.count == 1 ? 0 : 1.5, y: recentPhotos.count == 1 ? 0 : -0.5)
                    .id(latest.id)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .frame(width: 24, height: 24)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: recentPhotos.map(\.id))
    }
}

// MARK: - 单张正方形拍立得微缩卡片
private struct ThumbnailPolaroidCard: View {
    let photo: PhotoAsset
    @State private var thumbnail: UIImage?

    init(photo: PhotoAsset) {
        self.photo = photo
        let targetSize = CGSize(width: 60, height: 60)
        let cached = PhotoImageCache.shared.getPlaceholder(for: photo.id) ?? PhotoImageCache.shared.get(for: photo.id, targetSize: targetSize, isHighQuality: false)
        _thumbnail = State(initialValue: cached)
    }

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .strokeBorder(Color.white.opacity(0.95), lineWidth: 1.2)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 2, x: 0, y: 1)
        .task(id: photo.id) {
            if thumbnail == nil {
                await loadThumbnail()
            }
        }
    }

    private func loadThumbnail() async {
        let targetSize = CGSize(width: 60, height: 60)
        if let cached = PhotoImageCache.shared.getPlaceholder(for: photo.id) ?? PhotoImageCache.shared.get(for: photo.id, targetSize: targetSize, isHighQuality: false) {
            self.thumbnail = cached
            return
        }

        let manager = PHCachingImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        manager.requestImage(for: photo.asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
            if let image {
                Task { @MainActor in
                    self.thumbnail = image
                }
            }
        }
    }
}

#Preview {
    PendingPhotosEntryButton()
        .environmentObject(PhotoManager())
}
